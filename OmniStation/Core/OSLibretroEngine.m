// Motor libretro de OmniStation Dock (ver OSLibretroEngine.h).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Cómo va:
// • El núcleo se carga con dlopen (una vez; luego se reutiliza) y todas sus funciones se llaman
//   desde un único hilo de emulación, como pide libretro.
// • Imagen: el núcleo entrega cada fotograma (0RGB1555, RGB565 o XRGB8888); se pasa a BGRA y la
//   pantalla lo pinta en su CALayer al ritmo de la pantalla (CADisplayLink).
// • Sonido: anillo de muestras (un productor, un consumidor) que lee un AVAudioSourceNode.
// • Mando: el físico se lee con su manejador de cambios (GameController) y el táctil con botones;
//   el estado va en atómicos que el núcleo lee en input_state.
// • Partidas (.srm) al salir y cada pocos segundos si cambian; estado rápido (.state) en el menú.
// • Imagen por GPU (PS1, N64, PSP, Dreamcast): OpenGL ES 3. El núcleo pinta en un framebuffer
//   de OmniStation y cada fotograma se copia a la pantalla (CAEAGLLayer) desde el mismo hilo.
// • JIT: el núcleo lo usa solo si OmniStation lo tiene (depurador enganchado); si no, va en modo
//   intérprete. En iOS 26 sin depurador, las peticiones de JIT del núcleo (brk #0xf00d) se
//   contestan «no» en vez de cerrar la app.
#define GLES_SILENCE_DEPRECATION 1
// OpenGL ES está marcado como obsoleto, pero sigue en iOS y es lo que usan estos núcleos.
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#import "OSLibretroEngine.h"
#import "OSExternalDisplay.h"
#import "OSPerfHUD.h"
#import "OSRetroAPI.h"   // libretro.h (MIT), en plano para que no se pierda en el repo
// Vulkan (3DS y GameCube/Wii): sin enlazar con nada; las funciones se piden a MoltenVK.
#define VK_NO_PROTOTYPES 1
#define VK_USE_PLATFORM_METAL_EXT 1
#import "OSRetroVulkan.h" // libretro_vulkan.h (MIT); necesita Vendor/Vulkan-Headers

#import <AVFoundation/AVFoundation.h>
#import <GameController/GameController.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/EAGLDrawable.h>
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/ES3/glext.h>
#import <dlfcn.h>
#import <os/lock.h>
#import <stdatomic.h>
#import <mach/mach_time.h>
#import <mach/mach.h>
#import <sys/mman.h>
#import <stdarg.h>
#import <signal.h>
#import <sys/sysctl.h>
#import <sys/types.h>
#import <sys/utsname.h>
#import <unistd.h>
#import <pthread.h>
#import <os/proc.h>
#import <malloc/malloc.h>

extern int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);

#ifndef CS_OPS_STATUS
#define CS_OPS_STATUS 0
#endif
#ifndef CS_DEBUGGED
#define CS_DEBUGGED 0x10000000
#endif
#ifndef P_TRACED
#define P_TRACED 0x00000800
#endif

static NSString *OSLRText(NSString *language, NSString *spanish, NSString *english) {
    return [language isEqualToString:@"en"] ? english : spanish;
}

static double OSLRNow(void) {
    static mach_timebase_info_data_t info;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ mach_timebase_info(&info); });
    return (double)mach_absolute_time() * (double)info.numer / (double)info.denom / 1e9;
}

// MARK: - Funciones del núcleo

typedef struct {
    void (*init)(void);
    void (*deinit)(void);
    unsigned (*apiVersion)(void);
    void (*getSystemInfo)(struct retro_system_info *info);
    void (*getSystemAVInfo)(struct retro_system_av_info *info);
    void (*setEnvironment)(retro_environment_t callback);
    void (*setVideoRefresh)(retro_video_refresh_t callback);
    void (*setAudioSample)(retro_audio_sample_t callback);
    void (*setAudioSampleBatch)(retro_audio_sample_batch_t callback);
    void (*setInputPoll)(retro_input_poll_t callback);
    void (*setInputState)(retro_input_state_t callback);
    void (*setControllerPortDevice)(unsigned port, unsigned device);
    void (*reset)(void);
    void (*run)(void);
    size_t (*serializeSize)(void);
    bool (*serialize)(void *data, size_t size);
    bool (*unserialize)(const void *data, size_t size);
    bool (*loadGame)(const struct retro_game_info *game);
    void (*unloadGame)(void);
    void *(*getMemoryData)(unsigned id);
    size_t (*getMemorySize)(unsigned id);
} OSLRCore;

// MARK: - Estado de la partida (lo usan las funciones que llama el núcleo)

static OSLRCore gCore;
static enum retro_pixel_format gPixelFormat = RETRO_PIXEL_FORMAT_0RGB1555;
static char gSystemDir[1024];
static char gSaveDir[1024];
static char gCorePath[1024];
static unsigned gLanguage = RETRO_LANGUAGE_SPANISH;
/// Ruta del juego (algunos núcleos guardan el puntero mientras dura la partida).
static char gGamePath[2048];

// Opciones: las que pide OmniStation y las que declara el núcleo (con su valor por defecto).
// Solo se tocan desde el hilo de emulación.
static NSDictionary<NSString *, NSString *> *gUserOptions;
static NSMutableDictionary<NSString *, NSString *> *gDefaultOptions;
static NSMutableDictionary<NSString *, NSArray<NSString *> *> *gOptionValues;
static NSMutableDictionary<NSString *, NSData *> *gOptionStrings;

// Fotograma convertido a BGRA (lo pinta la pantalla).
static os_unfair_lock gFrameLock = OS_UNFAIR_LOCK_INIT;
// Opciones cambiadas desde el menú de la partida: el hilo de emulación las pasa al núcleo.
static NSMutableDictionary<NSString *, NSString *> *gPendingOptions;
static os_unfair_lock gPendingLock = OS_UNFAIR_LOCK_INIT;
static uint32_t *gFrame;
static size_t gFrameCapacity;
static unsigned gFrameWidth, gFrameHeight;
static _Atomic uint64_t gFrameSerial;
static _Atomic uint64_t gFrameCount;

// Geometría (relación de aspecto) y ritmo.
static _Atomic double gAspect = 4.0 / 3.0;
static double gFPS = 60.0;
static double gSampleRate = 44100.0;
static _Atomic bool gGeometryChanged;

// Sonido: anillo de muestras estéreo (16 bits). Un productor (núcleo) y un consumidor (audio).
static int16_t *gAudioRing;
static size_t gAudioCapacity; // en fotogramas de audio (pares L/R)
static _Atomic size_t gAudioWrite;
static _Atomic size_t gAudioRead;
static _Atomic float gVolume = 1.0f;
// Sonido «cebado»: empieza a sonar con un poco de margen y, si se vacía (el juego va lento o se
// para un instante al pedir JIT), vuelve a esperar ese margen en vez de sonar a trompicones.
static _Atomic bool gAudioPrimed;
// Última vez que el sonido pidió muestras: si no pide (sistema parado o sin salida), el bucle no
// espera a que haya sitio (si no, el juego se quedaría casi parado).
static _Atomic double gLastAudioPull;
// Memoria: lo mínimo libre durante la partida (para saber cuánto gasta cada sistema).
static size_t gSessionStartFree;
static size_t gSessionMinFree;

// Mando: bits RETRO_DEVICE_ID_JOYPAD_* del físico y del táctil; sticks; puntero (pantalla táctil).
static _Atomic uint32_t gPadBits;
static _Atomic uint32_t gTouchBits;
static _Atomic int32_t gAxis[4];
static _Atomic int32_t gPointerX, gPointerY;
static _Atomic bool gPointerDown;
static _Atomic bool gInputSuspended;

// Fotogramas por tiempo y peticiones del menú.
static struct retro_frame_time_callback gFrameTimeCallback;
static bool gHasFrameTimeCallback;
static _Atomic bool gShutdownRequested;
// Bucle de emulación: en marcha, en pausa (menú) y lo que pide el menú (-1: nada).
static _Atomic bool gRunning;
static _Atomic bool gPaused;
// En segundo plano no se puede usar la GPU (iOS cierra la app): el bucle espera.
static _Atomic bool gBackground;
static _Atomic int gPendingAction = -1;

typedef void (^OSLRMessageBlock)(NSString *message);
static OSLRMessageBlock gMessageHandler;

// Registro de cada partida (Archivos → OmniStation Dock → Registro libretro.txt): por dónde va al
// abrir y al cerrar, para saber dónde se queda si un núcleo no termina.
static NSString *OSLRTracePath(void) {
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject ?: NSTemporaryDirectory();
    return [documents stringByAppendingPathComponent:@"Registro libretro.txt"];
}

static void OSLRTrace(NSString *step, BOOL reset) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("omnistation.libretro.trace", DISPATCH_QUEUE_SERIAL); });
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate.date descriptionWithLocale:nil], step];
    dispatch_async(queue, ^{
        NSString *path = OSLRTracePath();
        if (reset || ![NSFileManager.defaultManager fileExistsAtPath:path]) {
            [line writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil];
            return;
        }
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        [handle seekToEndOfFile];
        [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    });
}

// El núcleo no terminó de cerrarse (se le esperó y no acabó): hasta reabrir la app no se puede
// abrir otro juego de estos núcleos (su hilo sigue ocupado).
static _Atomic bool gCoreStuck;
static _Atomic bool gLoopDone;

// Mando táctil: stick analógico (N64, PSP, Dreamcast) y botones C de N64 (stick derecho).
static _Atomic int32_t gTouchAxis[2];
static _Atomic bool gTouchStickActive;
static _Atomic uint32_t gTouchCBits; // 1 arriba, 2 abajo, 4 izquierda, 8 derecha

// JIT: si el núcleo puede usarlo en esta partida (con el depurador o con el bloque permanente).
static bool gJITCapable;
// El juego quiere JIT (ajuste «Usar JIT»): el bloque permanente solo se da si lo quiere.
static bool gJITWanted;
// Núcleo que pide su memoria de JIT a OmniStation, y si de verdad se le dio.
static bool gJITPoolCore;
static _Atomic bool gJITPoolGiven;
static _Atomic int gJITSmallLogged;   // bloques pequeños (sombreadores) apuntados en el registro

// Proporción sacada del propio fotograma (NDS: cambia con la colocación de las pantallas).
static bool gUseFrameAspect;
static unsigned gAspectFrameWidth, gAspectFrameHeight;

// Opción que cambia con la orientación (NDS: pantallas una encima de otra o al lado).
static NSString *gOrientKey;
static NSString *gOrientPortrait;
static NSString *gOrientLandscape;
static _Atomic int gOrientWanted = -1; // 1 vertical, 0 horizontal
static int gOrientApplied = -1;
static _Atomic bool gVariablesChanged;

// Imagen por GPU (OpenGL ES 3). Solo se toca desde el hilo de emulación, salvo la capa, que la
// crea la pantalla antes de arrancar.
static struct retro_hw_render_callback gHWCallback;
static bool gHWRequested;
static EAGLContext *gGLContext;
static GLuint gGLFramebuffer, gGLColorTexture, gGLDepthBuffer;
static unsigned gGLWidth, gGLHeight;
static GLuint gGLScreenFramebuffer, gGLScreenColor;
static GLint gGLScreenWidth, gGLScreenHeight;
static CAEAGLLayer *gGLLayer;
static _Atomic bool gGLLayerChanged;
static _Atomic bool gGLLayerShown;
static bool gGLSmooth;

// Juegos de varios discos: la interfaz de discos del núcleo (solo desde el hilo de emulación).
static struct retro_disk_control_ext_callback gDisk;
static bool gHasDisk;
static _Atomic unsigned gDiskCount;

// Imagen por GPU con Vulkan (MoltenVK): la capa la crea la pantalla antes de arrancar.
static CAMetalLayer *gMetalLayer;
static _Atomic bool gMetalLayerChanged;

// MARK: JIT y depurador

static BOOL OSLRIsDebugged(void) {
    uint32_t flags = 0;
    if (csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags)) != 0) return NO;
    return (flags & CS_DEBUGGED) != 0;
}

/// Hay un depurador enganchado ahora mismo (CS_DEBUGGED se queda aunque se suelte).
static BOOL OSLRIsTraced(void) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc info;
    size_t size = sizeof(info);
    memset(&info, 0, sizeof(info));
    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0) return NO;
    return (info.kp_proc.p_flag & P_TRACED) != 0;
}

static BOOL OSLRUsesJITScript(void) {
    return NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26;
}

// Sin depurador, un «brk #0xf00d» (petición de JIT del núcleo) cerraría la app: se contesta 0.
static struct sigaction gPreviousTrapAction;
static bool gTrapGuardInstalled;
// El núcleo pidió memoria de JIT (comando 1) y no había depurador que la preparase: esa partida
// va sin JIT de verdad (o el núcleo no puede seguir). Así el menú dice la verdad.
static volatile sig_atomic_t gJITUnanswered;

static void OSLRTrapHandler(int signalNumber, siginfo_t *info, void *context) {
    ucontext_t *state = (ucontext_t *)context;
    if (state != NULL && state->uc_mcontext != NULL) {
        uint64_t pc = state->uc_mcontext->__ss.__pc;
        uint32_t instruction = pc != 0 ? *(const uint32_t *)(uintptr_t)pc : 0;
        if (instruction == 0xD43E01A0u) { // brk #0xf00d
            if (state->uc_mcontext->__ss.__x[16] == 1) gJITUnanswered = 1;
            state->uc_mcontext->__ss.__pc = pc + 4;
            state->uc_mcontext->__ss.__x[0] = 0;
            return;
        }
    }
    // Otra trampa: lo de siempre.
    sigaction(SIGTRAP, &gPreviousTrapAction, NULL);
}

static void OSLRInstallTrapGuard(BOOL force) {
    if (gTrapGuardInstalled || !OSLRUsesJITScript() || (!force && OSLRIsTraced())) return;
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_sigaction = OSLRTrapHandler;
    action.sa_flags = SA_SIGINFO;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGTRAP, &action, &gPreviousTrapAction) == 0) gTrapGuardInstalled = true;
}

/// Suelta el depurador del script universal (comando 0): así la próxima vez se puede volver a
/// enganchar. Sin depurador, la trampa de arriba lo contesta.
__attribute__((noinline, naked)) static void OSLRUniversalDetach(void) {
    __asm__ volatile("mov x16, #0\n"
                     "brk #0xf00d\n"
                     "ret");
}

/// Pide al depurador (script universal, comando 1) que prepare `size` bytes en `address` para JIT.
__attribute__((noinline)) static void OSLRUniversalPrepare(void *address, size_t size) {
    register void *x0 __asm__("x0") = address;
    register size_t x1 __asm__("x1") = size;
    register uint64_t x16 __asm__("x16") = 1;
    __asm__ volatile("brk #0xf00d" : "+r"(x0), "+r"(x1) : "r"(x16) : "memory");
}

// MARK: JIT permanente (memoria de JIT que da OmniStation)
//
// Como DolphiniOS: un solo bloque grande de memoria de JIT para toda la vida de la app. Se prepara
// UNA vez con el depurador enganchado (comando 1 del script universal) y luego vale siempre,
// aunque el depurador se vaya: no hace falta volver a StikDebug ni a la VPN en cada partida.
// Se lo dan a los núcleos que lo piden con RETRO_ENVIRONMENT_EXEC_MEM_ALLOC (libretro estándar;
// el núcleo de Dolphin de libretro ya lo usa). Los de ManicEMU no lo piden: siguen como antes.
//
// Dos vistas de las mismas páginas: RX (se ejecuta) y RW (se escribe), como TXM exige.
#define OSLR_RETRO_ENVIRONMENT_EXEC_MEM_ALLOC 83
#define OSLR_RETRO_ENVIRONMENT_EXEC_MEM_FREE 84
#define OSLR_EXEC_MEM_MODE_UNAVAILABLE 0
#define OSLR_EXEC_MEM_MODE_UNRESTRICTED 1
#define OSLR_EXEC_MEM_MODE_DUAL_MAP 4
struct OSLRExecMemAlloc { unsigned version; size_t size; unsigned mode; void *rx; void *rw; };
struct OSLRExecMemFree { void *rx; };

static const size_t kOSLRJITPoolSize = (size_t)512 * 1024 * 1024; // como DolphiniOS
static const size_t kOSLRJITPage = 16384;
static uint8_t *gJITPoolRX;
static ptrdiff_t gJITPoolDiff;            // rw - rx
static uint32_t *gJITPoolRuns;            // en la primera página de cada bloque: cuántas páginas tiene
static uint8_t *gJITPoolUsed;             // 1 si la página está usada
static size_t gJITPoolPages;
static os_unfair_lock gJITPoolLock = OS_UNFAIR_LOCK_INIT;
// Bloques dados en la partida de ahora (se devuelven al cerrarla, como pide libretro).
static NSMutableArray<NSValue *> *gJITSessionBlocks;

/// Cómo quedó el último intento de preparar el bloque (para enseñarlo en Ajustes y en el menú).
static NSString *gJITPoolStatus;

/// Prepara el bloque (una vez). Necesita el depurador enganchado; si no, no hace nada.
static BOOL OSLRPrepareJITPool(void) {
    os_unfair_lock_lock(&gJITPoolLock);
    BOOL ready = gJITPoolRX != NULL;
    os_unfair_lock_unlock(&gJITPoolLock);
    if (ready) return YES;
    if (!OSLRUsesJITScript()) { gJITPoolStatus = @"no-txm"; return NO; }
    if (!OSLRIsDebugged() || !OSLRIsTraced()) { gJITPoolStatus = @"no-debugger"; return NO; }
    size_t size = kOSLRJITPoolSize;
    void *rx = mmap(NULL, size, PROT_READ | PROT_EXEC, MAP_ANON | MAP_PRIVATE, -1, 0);
    if (rx == MAP_FAILED) { gJITPoolStatus = [NSString stringWithFormat:@"mmap:%d", errno]; return NO; }
    // Si nadie contesta (no había depurador de verdad), la trampa lo dice y no se usa.
    OSLRInstallTrapGuard(YES);
    gJITUnanswered = 0;
    OSLRUniversalPrepare(rx, size);
    if (gJITUnanswered) {
        gJITUnanswered = 0;
        munmap(rx, size);
        gJITPoolStatus = @"unanswered";
        return NO;
    }
    vm_address_t rw = 0;
    vm_prot_t current = 0, maximum = 0;
    kern_return_t result = vm_remap(mach_task_self(), &rw, size, 0, VM_FLAGS_ANYWHERE, mach_task_self(),
                                    (vm_address_t)rx, FALSE, &current, &maximum, VM_INHERIT_DEFAULT);
    if (result != KERN_SUCCESS) {
        munmap(rx, size);
        gJITPoolStatus = [NSString stringWithFormat:@"vm_remap:0x%x", result];
        return NO;
    }
    if (mprotect((void *)rw, size, PROT_READ | PROT_WRITE) != 0) {
        int code = errno;
        vm_deallocate(mach_task_self(), rw, size);
        munmap(rx, size);
        gJITPoolStatus = [NSString stringWithFormat:@"mprotect:%d", code];
        return NO;
    }
    size_t pages = size / kOSLRJITPage;
    uint32_t *runs = calloc(pages, sizeof(uint32_t));
    uint8_t *used = calloc(pages, 1);
    if (runs == NULL || used == NULL) {
        free(runs);
        free(used);
        gJITPoolStatus = @"memory";
        return NO;
    }
    os_unfair_lock_lock(&gJITPoolLock);
    gJITPoolRuns = runs;
    gJITPoolUsed = used;
    gJITPoolPages = pages;
    gJITPoolDiff = (uint8_t *)rw - (uint8_t *)rx;
    gJITPoolRX = rx;
    os_unfair_lock_unlock(&gJITPoolLock);
    gJITPoolStatus = @"ready";
    printf("[OmniStation] JIT permanente listo: %zu MB\n", size / (1024 * 1024));
    return YES;
}

/// Un trozo del bloque (en páginas enteras, el primero libre donde quepa).
static void *OSLRJITPoolAllocate(size_t size) {
    if (size == 0) return NULL;
    size_t need = (size + kOSLRJITPage - 1) / kOSLRJITPage;
    void *result = NULL;
    os_unfair_lock_lock(&gJITPoolLock);
    if (gJITPoolRX != NULL) {
        size_t run = 0;
        for (size_t page = 0; page < gJITPoolPages; page++) {
            run = gJITPoolUsed[page] ? 0 : run + 1;
            if (run == need) {
                size_t first = page + 1 - need;
                memset(gJITPoolUsed + first, 1, need);
                gJITPoolRuns[first] = (uint32_t)need;
                result = gJITPoolRX + first * kOSLRJITPage;
                break;
            }
        }
    }
    os_unfair_lock_unlock(&gJITPoolLock);
    return result;
}

static BOOL OSLRJITPoolFree(void *pointer) {
    if (pointer == NULL) return NO;
    BOOL freed = NO;
    os_unfair_lock_lock(&gJITPoolLock);
    if (gJITPoolRX != NULL) {
        uint8_t *rx = pointer;
        // Vale también el puntero RW.
        if (rx >= gJITPoolRX + gJITPoolDiff && rx < gJITPoolRX + gJITPoolDiff + kOSLRJITPoolSize) rx -= gJITPoolDiff;
        if (rx >= gJITPoolRX && rx < gJITPoolRX + kOSLRJITPoolSize) {
            size_t first = (size_t)(rx - gJITPoolRX) / kOSLRJITPage;
            uint32_t count = gJITPoolRuns[first];
            if (count > 0) {
                // Lo que deja escrito un núcleo no debe verlo el siguiente.
                memset(gJITPoolRX + gJITPoolDiff + first * kOSLRJITPage, 0, (size_t)count * kOSLRJITPage);
                memset(gJITPoolUsed + first, 0, count);
                gJITPoolRuns[first] = 0;
                freed = YES;
            }
        }
    }
    os_unfair_lock_unlock(&gJITPoolLock);
    return freed;
}

// MARK: Opciones

static void OSLRRegisterOption(const char *key, const char *defaultValue, NSArray<NSString *> *values) {
    if (key == NULL) return;
    NSString *name = [NSString stringWithUTF8String:key];
    if (name.length == 0) return;
    NSString *value = defaultValue ? [NSString stringWithUTF8String:defaultValue] : values.firstObject;
    if (value) gDefaultOptions[name] = value;
    if (values.count) gOptionValues[name] = values;
}

static NSArray<NSString *> *OSLRValues(const struct retro_core_option_value *values) {
    NSMutableArray<NSString *> *list = [NSMutableArray new];
    for (int index = 0; index < RETRO_NUM_CORE_OPTION_VALUES_MAX && values[index].value != NULL; index++) {
        NSString *value = [NSString stringWithUTF8String:values[index].value];
        if (value) [list addObject:value];
    }
    return list;
}

static void OSLRRegisterV1(const struct retro_core_option_definition *definitions) {
    if (definitions == NULL) return;
    for (const struct retro_core_option_definition *item = definitions; item->key != NULL; item++) {
        OSLRRegisterOption(item->key, item->default_value, OSLRValues(item->values));
    }
}

static void OSLRRegisterV2(const struct retro_core_options_v2 *options) {
    if (options == NULL || options->definitions == NULL) return;
    for (const struct retro_core_option_v2_definition *item = options->definitions; item->key != NULL; item++) {
        OSLRRegisterOption(item->key, item->default_value, OSLRValues(item->values));
    }
}

/// «Descripción; a|b|c» (SET_VARIABLES): el primero es el de por defecto.
static void OSLRRegisterVariables(const struct retro_variable *variables) {
    if (variables == NULL) return;
    for (const struct retro_variable *item = variables; item->key != NULL; item++) {
        if (item->value == NULL) continue;
        NSString *text = [NSString stringWithUTF8String:item->value] ?: @"";
        NSRange separator = [text rangeOfString:@"; "];
        NSString *list = separator.location == NSNotFound ? text : [text substringFromIndex:NSMaxRange(separator)];
        NSArray<NSString *> *values = [list componentsSeparatedByString:@"|"];
        OSLRRegisterOption(item->key, NULL, values);
    }
}

/// Valor de una opción: el pedido por OmniStation si es válido; si no, el del núcleo.
static const char *OSLROptionValue(const char *key) {
    if (key == NULL) return NULL;
    NSString *name = [NSString stringWithUTF8String:key];
    if (name == nil) return NULL;
    NSString *value = gUserOptions[name];
    NSArray<NSString *> *allowed = gOptionValues[name];
    if (value != nil && allowed.count > 0 && ![allowed containsObject:value]) value = nil;
    if (value == nil) value = gDefaultOptions[name];
    if (value == nil) return NULL;
    NSData *stored = gOptionStrings[name];
    NSString *current = stored ? [NSString stringWithUTF8String:stored.bytes] : nil;
    if (![current isEqualToString:value]) {
        const char *utf8 = value.UTF8String;
        stored = [NSData dataWithBytes:utf8 length:strlen(utf8) + 1];
        gOptionStrings[name] = stored;
    }
    return stored.bytes;
}


/// Opciones para el menú de la partida, con el valor que usa ahora el núcleo.
static NSArray<NSMutableDictionary<NSString *, id> *> *OSLRMenuOptions(NSArray<NSDictionary<NSString *, id> *> *source) {
    NSMutableArray<NSMutableDictionary<NSString *, id> *> *menuOptions = [NSMutableArray new];
    for (NSDictionary<NSString *, id> *option in source ?: @[]) {
        NSString *key = option[@"key"];
        NSArray *values = option[@"values"];
        if (![key isKindOfClass:NSString.class] || ![values isKindOfClass:NSArray.class] || values.count < 2) continue;
        NSMutableDictionary<NSString *, id> *item = [option mutableCopy];
        if (gUserOptions[key]) item[@"value"] = gUserOptions[key];
        if (![item[@"value"] isKindOfClass:NSString.class]) item[@"value"] = [values.firstObject firstObject] ?: @"";
        [menuOptions addObject:item];
    }
    return menuOptions;
}

// MARK: Opciones que declara el núcleo (para los ajustes de cada núcleo)
//
// Para enseñar las opciones de un núcleo sin abrir ningún juego se le llama a
// retro_set_environment y se apunta lo que declara (claves, nombres, valores y categorías, en
// español si el núcleo lo trae traducido).

static BOOL gCapturing;
static NSMutableArray<NSMutableDictionary<NSString *, id> *> *gCaptured;
static NSMutableDictionary<NSString *, NSString *> *gCapturedCategories;
// En una partida de verdad también se apuntan (sin dejar de usarlas): así se conocen las de los
// núcleos que las declaran al prepararse (retro_init) sin tener que prepararlos aparte.
static BOOL gRecording;

/// Lo apuntado, con el nombre de cada categoría.
static NSArray<NSDictionary<NSString *, id> *> *OSLRCapturedList(void) {
    NSMutableArray<NSDictionary<NSString *, id> *> *result = [NSMutableArray new];
    for (NSMutableDictionary<NSString *, id> *entry in gCaptured) {
        NSMutableDictionary<NSString *, id> *item = [entry mutableCopy];
        NSString *category = item[@"category"];
        item[@"categoryTitle"] = category.length ? (gCapturedCategories[category] ?: @"") : @"";
        [result addObject:item];
    }
    return result;
}

static NSString *OSLRString(const char *text) {
    if (text == NULL) return @"";
    return [NSString stringWithUTF8String:text] ?: @"";
}

static NSArray<NSArray<NSString *> *> *OSLRCaptureValues(const struct retro_core_option_value *values) {
    NSMutableArray<NSArray<NSString *> *> *list = [NSMutableArray new];
    for (int index = 0; index < RETRO_NUM_CORE_OPTION_VALUES_MAX && values[index].value != NULL; index++) {
        NSString *value = OSLRString(values[index].value);
        NSString *label = values[index].label ? OSLRString(values[index].label) : value;
        if (value.length) [list addObject:@[value, label.length ? label : value]];
    }
    return list;
}

static NSMutableDictionary<NSString *, id> *OSLRCapturedEntry(NSString *key) {
    for (NSMutableDictionary<NSString *, id> *entry in gCaptured) {
        if ([entry[@"key"] isEqualToString:key]) return entry;
    }
    return nil;
}

/// Traducción («local»): cambia nombre, explicación y etiquetas de lo ya apuntado.
static void OSLRCaptureLocal(NSString *key, NSString *title, NSString *info, NSArray<NSArray<NSString *> *> *values) {
    NSMutableDictionary<NSString *, id> *entry = OSLRCapturedEntry(key);
    if (entry == nil) return;
    if (title.length) entry[@"title"] = title;
    if (info.length) entry[@"info"] = info;
    if (values.count == 0) return;
    NSMutableArray<NSArray<NSString *> *> *merged = [NSMutableArray new];
    for (NSArray<NSString *> *pair in entry[@"values"]) {
        NSString *label = pair[1];
        for (NSArray<NSString *> *local in values) {
            if ([local[0] isEqualToString:pair[0]]) { label = local[1]; break; }
        }
        [merged addObject:@[pair[0], label]];
    }
    entry[@"values"] = merged;
}

static void OSLRCaptureV2(const struct retro_core_options_v2 *options, BOOL local) {
    if (options == NULL) return;
    if (options->categories) {
        for (const struct retro_core_option_v2_category *item = options->categories; item->key != NULL; item++) {
            NSString *desc = OSLRString(item->desc);
            if (desc.length) gCapturedCategories[OSLRString(item->key)] = desc;
        }
    }
    if (options->definitions == NULL) return;
    for (const struct retro_core_option_v2_definition *item = options->definitions; item->key != NULL; item++) {
        NSString *key = OSLRString(item->key);
        NSString *title = OSLRString(item->desc_categorized ? item->desc_categorized : item->desc);
        if (title.length == 0) title = OSLRString(item->desc);
        NSString *info = OSLRString(item->info_categorized ? item->info_categorized : item->info);
        if (info.length == 0) info = OSLRString(item->info);
        NSArray<NSArray<NSString *> *> *values = OSLRCaptureValues(item->values);
        if (local) {
            OSLRCaptureLocal(key, title, info, values);
            continue;
        }
        if (key.length == 0 || values.count == 0 || OSLRCapturedEntry(key)) continue;
        [gCaptured addObject:[@{@"key": key, @"title": title.length ? title : key, @"info": info,
                                @"category": OSLRString(item->category_key),
                                @"default": item->default_value ? OSLRString(item->default_value) : values[0][0],
                                @"values": values} mutableCopy]];
    }
}

static void OSLRCaptureV1(const struct retro_core_option_definition *definitions, BOOL local) {
    if (definitions == NULL) return;
    for (const struct retro_core_option_definition *item = definitions; item->key != NULL; item++) {
        NSString *key = OSLRString(item->key);
        NSArray<NSArray<NSString *> *> *values = OSLRCaptureValues(item->values);
        if (local) {
            OSLRCaptureLocal(key, OSLRString(item->desc), OSLRString(item->info), values);
            continue;
        }
        if (key.length == 0 || values.count == 0 || OSLRCapturedEntry(key)) continue;
        [gCaptured addObject:[@{@"key": key, @"title": OSLRString(item->desc).length ? OSLRString(item->desc) : key,
                                @"info": OSLRString(item->info), @"category": @"",
                                @"default": item->default_value ? OSLRString(item->default_value) : values[0][0],
                                @"values": values} mutableCopy]];
    }
}

/// «Descripción; a|b|c» (SET_VARIABLES): el primero es el de por defecto.
static void OSLRCaptureVariables(const struct retro_variable *variables) {
    if (variables == NULL) return;
    for (const struct retro_variable *item = variables; item->key != NULL; item++) {
        if (item->value == NULL) continue;
        NSString *key = OSLRString(item->key);
        NSString *text = OSLRString(item->value);
        NSRange separator = [text rangeOfString:@"; "];
        NSString *title = separator.location == NSNotFound ? key : [text substringToIndex:separator.location];
        NSString *list = separator.location == NSNotFound ? text : [text substringFromIndex:NSMaxRange(separator)];
        NSMutableArray<NSArray<NSString *> *> *values = [NSMutableArray new];
        for (NSString *value in [list componentsSeparatedByString:@"|"]) {
            if (value.length) [values addObject:@[value, value]];
        }
        if (key.length == 0 || values.count == 0 || OSLRCapturedEntry(key)) continue;
        [gCaptured addObject:[@{@"key": key, @"title": title, @"info": @"", @"category": @"",
                                @"default": values[0][0], @"values": values} mutableCopy]];
    }
}

// MARK: Llamadas del núcleo

// Lo que cuenta el núcleo en la partida (desde «info»): «Registro núcleo.txt», junto al otro.
// Se escribe línea a línea y al momento, para que quede lo último si el núcleo se cierra de golpe.
static FILE *gCoreLogFile;
static size_t gCoreLogBytes;
static os_unfair_lock gCoreLogLock = OS_UNFAIR_LOCK_INIT;
static const size_t kOSLRCoreLogLimit = (size_t)4 * 1024 * 1024;

static void OSLRCoreLogReset(void) {
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject ?: NSTemporaryDirectory();
    NSString *path = [documents stringByAppendingPathComponent:@"Registro núcleo.txt"];
    os_unfair_lock_lock(&gCoreLogLock);
    if (gCoreLogFile) fclose(gCoreLogFile);
    gCoreLogFile = fopen(path.fileSystemRepresentation, "w");
    gCoreLogBytes = 0;
    os_unfair_lock_unlock(&gCoreLogLock);
}

static void OSLRLog(enum retro_log_level level, const char *format, ...) {
    if (format == NULL || level < RETRO_LOG_INFO) return;
    char line[2048];
    va_list args;
    va_start(args, format);
    int length = vsnprintf(line, sizeof(line), format, args);
    va_end(args);
    if (length <= 0) return;
    if (level >= RETRO_LOG_WARN) {
        fprintf(stdout, "[libretro] %s", line);
        fflush(stdout);
    }
    os_unfair_lock_lock(&gCoreLogLock);
    if (gCoreLogFile && gCoreLogBytes < kOSLRCoreLogLimit) {
        size_t size = strnlen(line, sizeof(line));
        fwrite(line, 1, size, gCoreLogFile);
        if (size == 0 || line[size - 1] != '\n') fputc('\n', gCoreLogFile);
        fflush(gCoreLogFile);
        gCoreLogBytes += size + 1;
    }
    os_unfair_lock_unlock(&gCoreLogLock);
}

// Último aviso del núcleo en esta partida (si no abre el juego, suele decir por qué).
static NSString *gLastCoreMessage;

static void OSLRShowMessage(const char *text) {
    if (text == NULL || text[0] == 0) return;
    NSString *message = [NSString stringWithUTF8String:text];
    if (message.length > 0) {
        @synchronized ([OSLibretroEngine class]) { gLastCoreMessage = message; }
    }
    OSLRMessageBlock handler = gMessageHandler;
    if (message.length == 0 || handler == nil) return;
    dispatch_async(dispatch_get_main_queue(), ^{ handler(message); });
}

static void OSLRUpdateGeometry(const struct retro_game_geometry *geometry) {
    if (geometry == NULL || gUseFrameAspect) return;
    double aspect = geometry->aspect_ratio;
    if (aspect <= 0 && geometry->base_height > 0) aspect = (double)geometry->base_width / (double)geometry->base_height;
    if (aspect > 0.1 && aspect < 10) {
        atomic_store(&gAspect, aspect);
        atomic_store(&gGeometryChanged, true);
    }
}

/// Proporción del fotograma tal cual (píxeles cuadrados), si la partida la usa.
static void OSLRNoteFrameSize(unsigned width, unsigned height) {
    if (!gUseFrameAspect || width == 0 || height == 0) return;
    if (width == gAspectFrameWidth && height == gAspectFrameHeight) return;
    gAspectFrameWidth = width;
    gAspectFrameHeight = height;
    atomic_store(&gAspect, (double)width / (double)height);
    atomic_store(&gGeometryChanged, true);
}

// MARK: Imagen por GPU

static uintptr_t OSLRCurrentFramebuffer(void) {
    return gGLFramebuffer;
}

static retro_proc_address_t OSLRProcAddress(const char *symbol) {
    if (symbol == NULL) return NULL;
    static void *library = NULL;
    if (library == NULL) library = dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES", RTLD_LAZY | RTLD_GLOBAL);
    void *address = library ? dlsym(library, symbol) : NULL;
    if (address == NULL) address = dlsym(RTLD_DEFAULT, symbol);
    return (retro_proc_address_t)address;
}

/// (Re)hace el sitio donde pinta el núcleo. Mantiene el mismo framebuffer (el núcleo lo pide
/// cada vez) y deja todo como estaba.
static void OSLRResizeGL(unsigned width, unsigned height) {
    GLint maximum = 4096;
    glGetIntegerv(GL_MAX_RENDERBUFFER_SIZE, &maximum);
    if (maximum < 1024) maximum = 1024;
    width = MIN(MAX(width, 16u), (unsigned)maximum);
    height = MIN(MAX(height, 16u), (unsigned)maximum);
    GLint previousTexture = 0, previousRenderbuffer = 0, previousFramebuffer = 0;
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &previousTexture);
    glGetIntegerv(GL_RENDERBUFFER_BINDING, &previousRenderbuffer);
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &previousFramebuffer);
    gGLWidth = width;
    gGLHeight = height;
    glBindTexture(GL_TEXTURE_2D, gGLColorTexture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, (GLsizei)width, (GLsizei)height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glBindRenderbuffer(GL_RENDERBUFFER, gGLDepthBuffer);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, (GLsizei)width, (GLsizei)height);
    glBindFramebuffer(GL_FRAMEBUFFER, gGLFramebuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, gGLColorTexture, 0);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, gGLDepthBuffer);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, gGLDepthBuffer);
    glBindTexture(GL_TEXTURE_2D, (GLuint)previousTexture);
    glBindRenderbuffer(GL_RENDERBUFFER, (GLuint)previousRenderbuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)previousFramebuffer);
}

/// Crea el contexto y el framebuffer del núcleo (después de cargar el juego).
static BOOL OSLRCreateGL(unsigned width, unsigned height) {
    gGLContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if (gGLContext == nil || ![EAGLContext setCurrentContext:gGLContext]) {
        gGLContext = nil;
        return NO;
    }
    glGenFramebuffers(1, &gGLFramebuffer);
    glGenTextures(1, &gGLColorTexture);
    glGenRenderbuffers(1, &gGLDepthBuffer);
    glGenFramebuffers(1, &gGLScreenFramebuffer);
    glGenRenderbuffers(1, &gGLScreenColor);
    OSLRResizeGL(width, height);
    glBindFramebuffer(GL_FRAMEBUFFER, gGLFramebuffer);
    BOOL complete = glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
    glViewport(0, 0, (GLsizei)gGLWidth, (GLsizei)gGLHeight);
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
    gGLScreenWidth = 0;
    gGLScreenHeight = 0;
    atomic_store(&gGLLayerChanged, true);
    return complete;
}

static void OSLRDestroyGL(void) {
    if (gGLContext == nil) return;
    [EAGLContext setCurrentContext:gGLContext];
    GLuint framebuffers[2] = {gGLFramebuffer, gGLScreenFramebuffer};
    GLuint renderbuffers[2] = {gGLDepthBuffer, gGLScreenColor};
    glDeleteFramebuffers(2, framebuffers);
    glDeleteRenderbuffers(2, renderbuffers);
    glDeleteTextures(1, &gGLColorTexture);
    gGLFramebuffer = gGLScreenFramebuffer = gGLDepthBuffer = gGLScreenColor = gGLColorTexture = 0;
    gGLWidth = gGLHeight = 0;
    [EAGLContext setCurrentContext:nil];
    gGLContext = nil;
}

/// Copia lo que ha pintado el núcleo (width × height) a la pantalla.
static void OSLRPresentGL(unsigned width, unsigned height) {
    if (gGLContext == nil || gGLLayer == nil || width == 0 || height == 0 || atomic_load(&gBackground)) return;
    GLint previousRead = 0, previousDraw = 0, previousRenderbuffer = 0;
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &previousRead);
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &previousDraw);
    glGetIntegerv(GL_RENDERBUFFER_BINDING, &previousRenderbuffer);
    if (atomic_exchange(&gGLLayerChanged, false)) {
        glBindRenderbuffer(GL_RENDERBUFFER, gGLScreenColor);
        gGLScreenWidth = 0;
        gGLScreenHeight = 0;
        if ([gGLContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:gGLLayer]) {
            glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &gGLScreenWidth);
            glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &gGLScreenHeight);
            glBindFramebuffer(GL_FRAMEBUFFER, gGLScreenFramebuffer);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, gGLScreenColor);
        }
    }
    if (gGLScreenWidth > 0 && gGLScreenHeight > 0) {
        GLboolean scissor = glIsEnabled(GL_SCISSOR_TEST);
        if (scissor) glDisable(GL_SCISSOR_TEST);
        GLint w = (GLint)MIN(width, gGLWidth), h = (GLint)MIN(height, gGLHeight);
        GLenum filter = gGLSmooth ? GL_LINEAR : GL_NEAREST;
        glBindFramebuffer(GL_READ_FRAMEBUFFER, gGLFramebuffer);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, gGLScreenFramebuffer);
        if (gHWCallback.bottom_left_origin) {
            glBlitFramebuffer(0, 0, w, h, 0, 0, gGLScreenWidth, gGLScreenHeight, GL_COLOR_BUFFER_BIT, filter);
        } else {
            glBlitFramebuffer(0, 0, w, h, 0, gGLScreenHeight, gGLScreenWidth, 0, GL_COLOR_BUFFER_BIT, filter);
        }
        if (scissor) glEnable(GL_SCISSOR_TEST);
        glBindRenderbuffer(GL_RENDERBUFFER, gGLScreenColor);
        [gGLContext presentRenderbuffer:GL_RENDERBUFFER];
        if (!atomic_exchange(&gGLLayerShown, true)) {
            dispatch_async(dispatch_get_main_queue(), ^{ gGLLayer.hidden = NO; });
        }
    }
    glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)previousRead);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, (GLuint)previousDraw);
    glBindRenderbuffer(GL_RENDERBUFFER, (GLuint)previousRenderbuffer);
}

// MARK: Imagen por GPU con Vulkan (MoltenVK)
//
// Como el controlador de Vulkan de RetroArch, en pequeño: OmniStation crea la instancia, el
// dispositivo (o deja que lo haga el núcleo con su interfaz de negociación), la superficie sobre
// una CAMetalLayer y la cadena de imágenes. El núcleo pinta en su imagen (set_image) y cada
// fotograma se copia (blit) a la pantalla. La cola se comparte con el núcleo (lock/unlock).

#define OSLR_VK_FRAMES 2
#define OSLR_VK_MAX_SWAP 8
#define OSLR_VK_MAX_WAITS 16

static struct {
    PFN_vkGetInstanceProcAddr GetInstanceProcAddr;
    PFN_vkGetDeviceProcAddr GetDeviceProcAddr;
    PFN_vkCreateInstance CreateInstance;
    PFN_vkEnumerateInstanceExtensionProperties EnumerateInstanceExtensionProperties;
    PFN_vkDestroyInstance DestroyInstance;
    PFN_vkEnumeratePhysicalDevices EnumeratePhysicalDevices;
    PFN_vkGetPhysicalDeviceFeatures GetPhysicalDeviceFeatures;
    PFN_vkGetPhysicalDeviceQueueFamilyProperties GetPhysicalDeviceQueueFamilyProperties;
    PFN_vkEnumerateDeviceExtensionProperties EnumerateDeviceExtensionProperties;
    PFN_vkCreateDevice CreateDevice;
    PFN_vkCreateMetalSurfaceEXT CreateMetalSurfaceEXT;
    PFN_vkDestroySurfaceKHR DestroySurfaceKHR;
    PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR GetPhysicalDeviceSurfaceCapabilitiesKHR;
    PFN_vkGetPhysicalDeviceSurfaceFormatsKHR GetPhysicalDeviceSurfaceFormatsKHR;
    PFN_vkDestroyDevice DestroyDevice;
    PFN_vkGetDeviceQueue GetDeviceQueue;
    PFN_vkDeviceWaitIdle DeviceWaitIdle;
    PFN_vkCreateSwapchainKHR CreateSwapchainKHR;
    PFN_vkDestroySwapchainKHR DestroySwapchainKHR;
    PFN_vkGetSwapchainImagesKHR GetSwapchainImagesKHR;
    PFN_vkAcquireNextImageKHR AcquireNextImageKHR;
    PFN_vkQueuePresentKHR QueuePresentKHR;
    PFN_vkQueueSubmit QueueSubmit;
    PFN_vkCreateCommandPool CreateCommandPool;
    PFN_vkDestroyCommandPool DestroyCommandPool;
    PFN_vkAllocateCommandBuffers AllocateCommandBuffers;
    PFN_vkBeginCommandBuffer BeginCommandBuffer;
    PFN_vkEndCommandBuffer EndCommandBuffer;
    PFN_vkResetCommandBuffer ResetCommandBuffer;
    PFN_vkCmdPipelineBarrier CmdPipelineBarrier;
    PFN_vkCmdBlitImage CmdBlitImage;
    PFN_vkCreateFence CreateFence;
    PFN_vkDestroyFence DestroyFence;
    PFN_vkWaitForFences WaitForFences;
    PFN_vkResetFences ResetFences;
    PFN_vkCreateSemaphore CreateSemaphore;
    PFN_vkDestroySemaphore DestroySemaphore;
} vk;

static void *gVKLibrary;
static VkInstance gVKInstance;
static VkPhysicalDevice gVKGPU;
static VkDevice gVKDevice;
static VkQueue gVKQueue;
static uint32_t gVKQueueFamily;
static VkSurfaceKHR gVKSurface;
static VkSwapchainKHR gVKSwapchain;
static VkExtent2D gVKSwapExtent;
static uint32_t gVKSwapCount;
static VkImage gVKSwapImages[OSLR_VK_MAX_SWAP];
static VkSemaphore gVKRendered[OSLR_VK_MAX_SWAP];
static VkCommandPool gVKPool;
static VkCommandBuffer gVKCommands[OSLR_VK_FRAMES];
static VkFence gVKFences[OSLR_VK_FRAMES];
static VkSemaphore gVKAcquired[OSLR_VK_FRAMES];
static uint32_t gVKFrame;
static bool gVKPortabilitySubset;
static pthread_mutex_t gVKQueueLock = PTHREAD_MUTEX_INITIALIZER;
// Lo que manda el núcleo para el fotograma.
static struct retro_vulkan_image gVKImage;
static bool gVKHasImage;
static VkSemaphore gVKWaits[OSLR_VK_MAX_WAITS];
static VkPipelineStageFlags gVKWaitStages[OSLR_VK_MAX_WAITS];
static uint32_t gVKWaitCount;
static VkCommandBuffer gVKCoreCommands[OSLR_VK_MAX_WAITS];
static uint32_t gVKCoreCommandCount;
static VkSemaphore gVKSignal;
static struct retro_hw_render_interface_vulkan gVKInterface;
static const struct retro_hw_render_context_negotiation_interface_vulkan *gVKNegotiation;
static bool gVKCoreCreatedDevice;

static BOOL OSLRLoadVulkanLibrary(void) {
    if (gVKLibrary != NULL) return vk.GetInstanceProcAddr != NULL;
    NSString *frameworks = NSBundle.mainBundle.privateFrameworksPath ?: [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks"];
    // El de MeloNX si va (así solo hay un MoltenVK en la app); si no, el de los núcleos.
    NSArray<NSString *> *candidates = @[@"libMoltenVK.dylib", @"MoltenVK.framework/MoltenVK"];
    for (NSString *relative in candidates) {
        NSString *path = [frameworks stringByAppendingPathComponent:relative];
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) continue;
        gVKLibrary = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
        if (gVKLibrary != NULL) break;
    }
    if (gVKLibrary == NULL) return NO;
    vk.GetInstanceProcAddr = (PFN_vkGetInstanceProcAddr)dlsym(gVKLibrary, "vkGetInstanceProcAddr");
    if (vk.GetInstanceProcAddr == NULL) return NO;
    vk.CreateInstance = (PFN_vkCreateInstance)vk.GetInstanceProcAddr(VK_NULL_HANDLE, "vkCreateInstance");
    vk.EnumerateInstanceExtensionProperties = (PFN_vkEnumerateInstanceExtensionProperties)vk.GetInstanceProcAddr(VK_NULL_HANDLE, "vkEnumerateInstanceExtensionProperties");
    return vk.CreateInstance != NULL;
}

static void OSLRLoadInstanceFunctions(VkInstance instance) {
    #define OSLR_VKI(name) vk.name = (PFN_vk##name)vk.GetInstanceProcAddr(instance, "vk" #name)
    OSLR_VKI(GetDeviceProcAddr);
    OSLR_VKI(DestroyInstance);
    OSLR_VKI(EnumeratePhysicalDevices);
    OSLR_VKI(GetPhysicalDeviceFeatures);
    OSLR_VKI(GetPhysicalDeviceQueueFamilyProperties);
    OSLR_VKI(EnumerateDeviceExtensionProperties);
    OSLR_VKI(CreateDevice);
    OSLR_VKI(CreateMetalSurfaceEXT);
    OSLR_VKI(DestroySurfaceKHR);
    OSLR_VKI(GetPhysicalDeviceSurfaceCapabilitiesKHR);
    OSLR_VKI(GetPhysicalDeviceSurfaceFormatsKHR);
    #undef OSLR_VKI
}

static void OSLRLoadDeviceFunctions(VkDevice device) {
    #define OSLR_VKD(name) vk.name = (PFN_vk##name)vk.GetDeviceProcAddr(device, "vk" #name)
    OSLR_VKD(DestroyDevice);
    OSLR_VKD(GetDeviceQueue);
    OSLR_VKD(DeviceWaitIdle);
    OSLR_VKD(CreateSwapchainKHR);
    OSLR_VKD(DestroySwapchainKHR);
    OSLR_VKD(GetSwapchainImagesKHR);
    OSLR_VKD(AcquireNextImageKHR);
    OSLR_VKD(QueuePresentKHR);
    OSLR_VKD(QueueSubmit);
    OSLR_VKD(CreateCommandPool);
    OSLR_VKD(DestroyCommandPool);
    OSLR_VKD(AllocateCommandBuffers);
    OSLR_VKD(BeginCommandBuffer);
    OSLR_VKD(EndCommandBuffer);
    OSLR_VKD(ResetCommandBuffer);
    OSLR_VKD(CmdPipelineBarrier);
    OSLR_VKD(CmdBlitImage);
    OSLR_VKD(CreateFence);
    OSLR_VKD(DestroyFence);
    OSLR_VKD(WaitForFences);
    OSLR_VKD(ResetFences);
    OSLR_VKD(CreateSemaphore);
    OSLR_VKD(DestroySemaphore);
    #undef OSLR_VKD
}

/// Junta las extensiones pedidas con las que necesita OmniStation (sin repetir).
static NSArray<NSString *> *OSLRMergeExtensions(const char *const *names, uint32_t count, NSArray<NSString *> *extra) {
    NSMutableArray<NSString *> *list = [NSMutableArray new];
    for (uint32_t index = 0; index < count; index++) {
        if (names[index] == NULL) continue;
        NSString *name = [NSString stringWithUTF8String:names[index]];
        if (name && ![list containsObject:name]) [list addObject:name];
    }
    for (NSString *name in extra) {
        if (![list containsObject:name]) [list addObject:name];
    }
    return list;
}

/// Punteros C de una lista (viven mientras viva `storage`).
static const char **OSLRCStrings(NSArray<NSString *> *list, NSMutableData *storage) {
    [storage setLength:sizeof(char *) * MAX(list.count, 1u)];
    const char **pointers = (const char **)storage.mutableBytes;
    for (NSUInteger index = 0; index < list.count; index++) pointers[index] = list[index].UTF8String;
    return pointers;
}

static NSArray<NSString *> *OSLRInstanceExtensions(void) {
    NSMutableArray<NSString *> *wanted = [NSMutableArray arrayWithArray:@[@VK_KHR_SURFACE_EXTENSION_NAME, @VK_EXT_METAL_SURFACE_EXTENSION_NAME]];
    // Si MoltenVK la tiene, la de propiedades 2 (la piden muchos núcleos).
    uint32_t count = 0;
    if (vk.EnumerateInstanceExtensionProperties && vk.EnumerateInstanceExtensionProperties(NULL, &count, NULL) == VK_SUCCESS && count > 0) {
        VkExtensionProperties *properties = calloc(count, sizeof(VkExtensionProperties));
        if (properties && vk.EnumerateInstanceExtensionProperties(NULL, &count, properties) == VK_SUCCESS) {
            for (uint32_t index = 0; index < count; index++) {
                if (strcmp(properties[index].extensionName, VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME) == 0) {
                    [wanted addObject:@VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME];
                }
            }
        }
        free(properties);
    }
    return wanted;
}

static NSArray<NSString *> *OSLRDeviceExtensions(VkPhysicalDevice gpu) {
    NSMutableArray<NSString *> *wanted = [NSMutableArray arrayWithObject:@VK_KHR_SWAPCHAIN_EXTENSION_NAME];
    gVKPortabilitySubset = false;
    uint32_t count = 0;
    if (vk.EnumerateDeviceExtensionProperties && vk.EnumerateDeviceExtensionProperties(gpu, NULL, &count, NULL) == VK_SUCCESS && count > 0) {
        VkExtensionProperties *properties = calloc(count, sizeof(VkExtensionProperties));
        if (properties && vk.EnumerateDeviceExtensionProperties(gpu, NULL, &count, properties) == VK_SUCCESS) {
            for (uint32_t index = 0; index < count; index++) {
                // MoltenVK: si existe, hay que activarla.
                if (strcmp(properties[index].extensionName, "VK_KHR_portability_subset") == 0) {
                    [wanted addObject:@"VK_KHR_portability_subset"];
                    gVKPortabilitySubset = true;
                }
            }
        }
        free(properties);
    }
    return wanted;
}

static VkInstance OSLRCreateInstanceWrapper(void *opaque, const VkInstanceCreateInfo *createInfo) {
    if (createInfo == NULL) return VK_NULL_HANDLE;
    VkInstanceCreateInfo info = *createInfo;
    NSArray<NSString *> *extensions = OSLRMergeExtensions(createInfo->ppEnabledExtensionNames, createInfo->enabledExtensionCount, OSLRInstanceExtensions());
    NSMutableData *storage = [NSMutableData new];
    info.ppEnabledExtensionNames = OSLRCStrings(extensions, storage);
    info.enabledExtensionCount = (uint32_t)extensions.count;
    VkInstance instance = VK_NULL_HANDLE;
    if (vk.CreateInstance(&info, NULL, &instance) != VK_SUCCESS) return VK_NULL_HANDLE;
    return instance;
}

static VkDevice OSLRCreateDeviceWrapper(VkPhysicalDevice gpu, void *opaque, const VkDeviceCreateInfo *createInfo) {
    if (createInfo == NULL) return VK_NULL_HANDLE;
    VkDeviceCreateInfo info = *createInfo;
    NSArray<NSString *> *extensions = OSLRMergeExtensions(createInfo->ppEnabledExtensionNames, createInfo->enabledExtensionCount, OSLRDeviceExtensions(gpu));
    NSMutableData *storage = [NSMutableData new];
    info.ppEnabledExtensionNames = OSLRCStrings(extensions, storage);
    info.enabledExtensionCount = (uint32_t)extensions.count;
    VkDevice device = VK_NULL_HANDLE;
    if (vk.CreateDevice(gpu, &info, NULL, &device) != VK_SUCCESS) return VK_NULL_HANDLE;
    return device;
}

// Lo que el núcleo llama durante la partida.
static void OSLRVKSetImage(void *handle, const struct retro_vulkan_image *image, uint32_t count, const VkSemaphore *semaphores, uint32_t sourceFamily) {
    if (image == NULL) {
        gVKHasImage = false;
        return;
    }
    gVKImage = *image;
    gVKHasImage = true;
    gVKWaitCount = 0;
    for (uint32_t index = 0; index < count && index < OSLR_VK_MAX_WAITS; index++) {
        gVKWaits[gVKWaitCount] = semaphores[index];
        gVKWaitStages[gVKWaitCount] = VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
        gVKWaitCount++;
    }
}

static uint32_t OSLRVKSyncIndex(void *handle) { return gVKFrame; }
static uint32_t OSLRVKSyncIndexMask(void *handle) { return (1u << OSLR_VK_FRAMES) - 1u; }

static void OSLRVKSetCommandBuffers(void *handle, uint32_t count, const VkCommandBuffer *commands) {
    gVKCoreCommandCount = 0;
    for (uint32_t index = 0; index < count && index < OSLR_VK_MAX_WAITS; index++) {
        gVKCoreCommands[gVKCoreCommandCount++] = commands[index];
    }
}

static void OSLRVKWaitSyncIndex(void *handle) {
    if (gVKDevice == VK_NULL_HANDLE) return;
    vk.WaitForFences(gVKDevice, 1, &gVKFences[gVKFrame], VK_TRUE, UINT64_MAX);
}

static void OSLRVKLockQueue(void *handle) { pthread_mutex_lock(&gVKQueueLock); }
static void OSLRVKUnlockQueue(void *handle) { pthread_mutex_unlock(&gVKQueueLock); }
static void OSLRVKSetSignalSemaphore(void *handle, VkSemaphore semaphore) { gVKSignal = semaphore; }

static void OSLRDestroySwapchain(void) {
    if (gVKDevice == VK_NULL_HANDLE) return;
    for (uint32_t index = 0; index < OSLR_VK_MAX_SWAP; index++) {
        if (gVKRendered[index] != VK_NULL_HANDLE) vk.DestroySemaphore(gVKDevice, gVKRendered[index], NULL);
        gVKRendered[index] = VK_NULL_HANDLE;
    }
    if (gVKSwapchain != VK_NULL_HANDLE) vk.DestroySwapchainKHR(gVKDevice, gVKSwapchain, NULL);
    gVKSwapchain = VK_NULL_HANDLE;
    gVKSwapCount = 0;
}

/// (Re)hace la cadena de imágenes con el tamaño de la capa. NO si ahora no se puede (capa sin tamaño).
static BOOL OSLRCreateSwapchain(void) {
    pthread_mutex_lock(&gVKQueueLock);
    vk.DeviceWaitIdle(gVKDevice);
    pthread_mutex_unlock(&gVKQueueLock);
    VkSwapchainKHR old = gVKSwapchain;
    for (uint32_t index = 0; index < OSLR_VK_MAX_SWAP; index++) {
        if (gVKRendered[index] != VK_NULL_HANDLE) vk.DestroySemaphore(gVKDevice, gVKRendered[index], NULL);
        gVKRendered[index] = VK_NULL_HANDLE;
    }
    gVKSwapCount = 0;
    VkSurfaceCapabilitiesKHR caps;
    memset(&caps, 0, sizeof(caps));
    if (vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(gVKGPU, gVKSurface, &caps) != VK_SUCCESS) return NO;
    VkExtent2D extent = caps.currentExtent;
    if (extent.width == UINT32_MAX || extent.width == 0) {
        CGSize size = gMetalLayer.drawableSize;
        extent.width = (uint32_t)MAX(size.width, 0);
        extent.height = (uint32_t)MAX(size.height, 0);
    }
    if (extent.width == 0 || extent.height == 0) {
        if (old != VK_NULL_HANDLE) vk.DestroySwapchainKHR(gVKDevice, old, NULL);
        gVKSwapchain = VK_NULL_HANDLE;
        return NO;
    }
    uint32_t formatCount = 0;
    vk.GetPhysicalDeviceSurfaceFormatsKHR(gVKGPU, gVKSurface, &formatCount, NULL);
    VkSurfaceFormatKHR chosen = {VK_FORMAT_B8G8R8A8_UNORM, VK_COLOR_SPACE_SRGB_NONLINEAR_KHR};
    if (formatCount > 0) {
        VkSurfaceFormatKHR *formats = calloc(formatCount, sizeof(VkSurfaceFormatKHR));
        if (formats && vk.GetPhysicalDeviceSurfaceFormatsKHR(gVKGPU, gVKSurface, &formatCount, formats) == VK_SUCCESS) {
            chosen = formats[0];
            for (uint32_t index = 0; index < formatCount; index++) {
                if (formats[index].format == VK_FORMAT_B8G8R8A8_UNORM) { chosen = formats[index]; break; }
            }
        }
        free(formats);
    }
    uint32_t minimum = MAX(caps.minImageCount, 3u);
    if (caps.maxImageCount > 0) minimum = MIN(minimum, caps.maxImageCount);
    VkCompositeAlphaFlagBitsKHR alpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    if (!(caps.supportedCompositeAlpha & alpha)) {
        for (uint32_t bit = 1; bit <= VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR; bit <<= 1) {
            if (caps.supportedCompositeAlpha & bit) { alpha = (VkCompositeAlphaFlagBitsKHR)bit; break; }
        }
    }
    VkSwapchainCreateInfoKHR info;
    memset(&info, 0, sizeof(info));
    info.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    info.surface = gVKSurface;
    info.minImageCount = minimum;
    info.imageFormat = chosen.format;
    info.imageColorSpace = chosen.colorSpace;
    info.imageExtent = extent;
    info.imageArrayLayers = 1;
    info.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    info.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    info.preTransform = caps.currentTransform;
    info.compositeAlpha = alpha;
    info.presentMode = VK_PRESENT_MODE_FIFO_KHR;
    info.clipped = VK_TRUE;
    info.oldSwapchain = old;
    VkSwapchainKHR swapchain = VK_NULL_HANDLE;
    VkResult result = vk.CreateSwapchainKHR(gVKDevice, &info, NULL, &swapchain);
    if (old != VK_NULL_HANDLE) vk.DestroySwapchainKHR(gVKDevice, old, NULL);
    gVKSwapchain = VK_NULL_HANDLE;
    if (result != VK_SUCCESS) return NO;
    uint32_t count = 0;
    vk.GetSwapchainImagesKHR(gVKDevice, swapchain, &count, NULL);
    count = MIN(count, (uint32_t)OSLR_VK_MAX_SWAP);
    vk.GetSwapchainImagesKHR(gVKDevice, swapchain, &count, gVKSwapImages);
    VkSemaphoreCreateInfo semaphoreInfo = {VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO, NULL, 0};
    for (uint32_t index = 0; index < count; index++) vk.CreateSemaphore(gVKDevice, &semaphoreInfo, NULL, &gVKRendered[index]);
    gVKSwapchain = swapchain;
    gVKSwapCount = count;
    gVKSwapExtent = extent;
    return YES;
}

/// Crea todo lo de Vulkan después de cargar el juego (antes de context_reset).
static BOOL OSLRCreateVulkan(void) {
    if (gMetalLayer == nil || !OSLRLoadVulkanLibrary()) return NO;
    const struct retro_hw_render_context_negotiation_interface_vulkan *negotiation = gVKNegotiation;
    VkApplicationInfo defaultApp = {VK_STRUCTURE_TYPE_APPLICATION_INFO, NULL, "OmniStation Dock", 1, "OmniStation", 1, VK_API_VERSION_1_1};
    const VkApplicationInfo *app = &defaultApp;
    if (negotiation && negotiation->get_application_info) {
        const VkApplicationInfo *coreApp = negotiation->get_application_info();
        if (coreApp) app = coreApp;
    }
    // Instancia: la del núcleo (negociación v2) o la de OmniStation.
    if (negotiation && negotiation->interface_version >= 2 && negotiation->create_instance) {
        gVKInstance = negotiation->create_instance(vk.GetInstanceProcAddr, app, OSLRCreateInstanceWrapper, NULL);
    }
    if (gVKInstance == VK_NULL_HANDLE) {
        VkInstanceCreateInfo info;
        memset(&info, 0, sizeof(info));
        info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
        info.pApplicationInfo = app;
        gVKInstance = OSLRCreateInstanceWrapper(NULL, &info);
    }
    if (gVKInstance == VK_NULL_HANDLE) return NO;
    OSLRLoadInstanceFunctions(gVKInstance);
    if (vk.CreateMetalSurfaceEXT == NULL || vk.GetDeviceProcAddr == NULL) return NO;
    VkMetalSurfaceCreateInfoEXT surfaceInfo = {
        .sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT,
        .pNext = NULL,
        .flags = 0,
        .pLayer = gMetalLayer,
    };
    if (vk.CreateMetalSurfaceEXT(gVKInstance, &surfaceInfo, NULL, &gVKSurface) != VK_SUCCESS) return NO;
    uint32_t gpuCount = 1;
    VkPhysicalDevice gpu = VK_NULL_HANDLE;
    if (vk.EnumeratePhysicalDevices(gVKInstance, &gpuCount, &gpu) < 0 || gpu == VK_NULL_HANDLE) return NO;
    // Dispositivo: el del núcleo (negociación) o el de OmniStation.
    struct retro_vulkan_context context;
    memset(&context, 0, sizeof(context));
    BOOL created = NO;
    if (negotiation && negotiation->interface_version >= 2 && negotiation->create_device2) {
        created = negotiation->create_device2(&context, gVKInstance, gpu, gVKSurface, vk.GetInstanceProcAddr, OSLRCreateDeviceWrapper, NULL);
        if (!created) {
            memset(&context, 0, sizeof(context));
            created = negotiation->create_device2(&context, gVKInstance, VK_NULL_HANDLE, gVKSurface, vk.GetInstanceProcAddr, OSLRCreateDeviceWrapper, NULL);
        }
    } else if (negotiation && negotiation->create_device) {
        NSArray<NSString *> *extensions = OSLRDeviceExtensions(gpu);
        NSMutableData *storage = [NSMutableData new];
        const char **names = OSLRCStrings(extensions, storage);
        VkPhysicalDeviceFeatures features;
        memset(&features, 0, sizeof(features));
        created = negotiation->create_device(&context, gVKInstance, gpu, gVKSurface, vk.GetInstanceProcAddr,
                                             names, (unsigned)extensions.count, NULL, 0, &features);
    }
    if (created && context.device != VK_NULL_HANDLE) {
        gVKCoreCreatedDevice = true;
        gVKGPU = context.gpu;
        gVKDevice = context.device;
        gVKQueue = context.queue;
        gVKQueueFamily = context.queue_family_index;
    } else {
        // Como RetroArch sin negociación: una cola de gráficos y todas las funciones que tenga la GPU.
        gVKGPU = gpu;
        uint32_t familyCount = 0;
        vk.GetPhysicalDeviceQueueFamilyProperties(gpu, &familyCount, NULL);
        VkQueueFamilyProperties families[16];
        familyCount = MIN(familyCount, 16u);
        vk.GetPhysicalDeviceQueueFamilyProperties(gpu, &familyCount, families);
        gVKQueueFamily = 0;
        for (uint32_t index = 0; index < familyCount; index++) {
            if (families[index].queueFlags & VK_QUEUE_GRAPHICS_BIT) { gVKQueueFamily = index; break; }
        }
        float priority = 1.0f;
        VkDeviceQueueCreateInfo queueInfo;
        memset(&queueInfo, 0, sizeof(queueInfo));
        queueInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        queueInfo.queueFamilyIndex = gVKQueueFamily;
        queueInfo.queueCount = 1;
        queueInfo.pQueuePriorities = &priority;
        VkPhysicalDeviceFeatures features;
        memset(&features, 0, sizeof(features));
        vk.GetPhysicalDeviceFeatures(gpu, &features);
        features.robustBufferAccess = VK_FALSE;
        VkDeviceCreateInfo info;
        memset(&info, 0, sizeof(info));
        info.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        info.queueCreateInfoCount = 1;
        info.pQueueCreateInfos = &queueInfo;
        info.pEnabledFeatures = &features;
        gVKDevice = OSLRCreateDeviceWrapper(gpu, NULL, &info);
        if (gVKDevice == VK_NULL_HANDLE) return NO;
        OSLRLoadDeviceFunctions(gVKDevice);
        vk.GetDeviceQueue(gVKDevice, gVKQueueFamily, 0, &gVKQueue);
    }
    OSLRLoadDeviceFunctions(gVKDevice);
    if (vk.QueueSubmit == NULL || vk.CreateSwapchainKHR == NULL || gVKQueue == VK_NULL_HANDLE) return NO;
    // Lo de cada fotograma.
    VkCommandPoolCreateInfo poolInfo;
    memset(&poolInfo, 0, sizeof(poolInfo));
    poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    poolInfo.queueFamilyIndex = gVKQueueFamily;
    if (vk.CreateCommandPool(gVKDevice, &poolInfo, NULL, &gVKPool) != VK_SUCCESS) return NO;
    VkCommandBufferAllocateInfo allocate;
    memset(&allocate, 0, sizeof(allocate));
    allocate.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    allocate.commandPool = gVKPool;
    allocate.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    allocate.commandBufferCount = OSLR_VK_FRAMES;
    if (vk.AllocateCommandBuffers(gVKDevice, &allocate, gVKCommands) != VK_SUCCESS) return NO;
    VkFenceCreateInfo fenceInfo = {VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, NULL, VK_FENCE_CREATE_SIGNALED_BIT};
    VkSemaphoreCreateInfo semaphoreInfo = {VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO, NULL, 0};
    for (uint32_t index = 0; index < OSLR_VK_FRAMES; index++) {
        vk.CreateFence(gVKDevice, &fenceInfo, NULL, &gVKFences[index]);
        vk.CreateSemaphore(gVKDevice, &semaphoreInfo, NULL, &gVKAcquired[index]);
    }
    gVKFrame = 0;
    atomic_store(&gMetalLayerChanged, true);
    // La interfaz que pide el núcleo (GET_HW_RENDER_INTERFACE).
    memset(&gVKInterface, 0, sizeof(gVKInterface));
    gVKInterface.interface_type = RETRO_HW_RENDER_INTERFACE_VULKAN;
    gVKInterface.interface_version = RETRO_HW_RENDER_INTERFACE_VULKAN_VERSION;
    gVKInterface.handle = &gVKInterface;
    gVKInterface.instance = gVKInstance;
    gVKInterface.gpu = gVKGPU;
    gVKInterface.device = gVKDevice;
    gVKInterface.get_device_proc_addr = vk.GetDeviceProcAddr;
    gVKInterface.get_instance_proc_addr = vk.GetInstanceProcAddr;
    gVKInterface.queue = gVKQueue;
    gVKInterface.queue_index = gVKQueueFamily;
    gVKInterface.set_image = OSLRVKSetImage;
    gVKInterface.get_sync_index = OSLRVKSyncIndex;
    gVKInterface.get_sync_index_mask = OSLRVKSyncIndexMask;
    gVKInterface.set_command_buffers = OSLRVKSetCommandBuffers;
    gVKInterface.wait_sync_index = OSLRVKWaitSyncIndex;
    gVKInterface.lock_queue = OSLRVKLockQueue;
    gVKInterface.unlock_queue = OSLRVKUnlockQueue;
    gVKInterface.set_signal_semaphore = OSLRVKSetSignalSemaphore;
    return YES;
}

static void OSLRDestroyVulkan(void) {
    if (gVKDevice != VK_NULL_HANDLE) {
        pthread_mutex_lock(&gVKQueueLock);
        vk.DeviceWaitIdle(gVKDevice);
        pthread_mutex_unlock(&gVKQueueLock);
        OSLRDestroySwapchain();
        for (uint32_t index = 0; index < OSLR_VK_FRAMES; index++) {
            if (gVKFences[index] != VK_NULL_HANDLE) vk.DestroyFence(gVKDevice, gVKFences[index], NULL);
            if (gVKAcquired[index] != VK_NULL_HANDLE) vk.DestroySemaphore(gVKDevice, gVKAcquired[index], NULL);
            gVKFences[index] = VK_NULL_HANDLE;
            gVKAcquired[index] = VK_NULL_HANDLE;
            gVKCommands[index] = VK_NULL_HANDLE;
        }
        if (gVKPool != VK_NULL_HANDLE) vk.DestroyCommandPool(gVKDevice, gVKPool, NULL);
        gVKPool = VK_NULL_HANDLE;
    }
    // Lo propio del núcleo, antes de que se vaya el dispositivo.
    if (gVKCoreCreatedDevice && gVKNegotiation && gVKNegotiation->destroy_device) gVKNegotiation->destroy_device();
    if (gVKDevice != VK_NULL_HANDLE) vk.DestroyDevice(gVKDevice, NULL);
    if (gVKSurface != VK_NULL_HANDLE && vk.DestroySurfaceKHR) vk.DestroySurfaceKHR(gVKInstance, gVKSurface, NULL);
    if (gVKInstance != VK_NULL_HANDLE && vk.DestroyInstance) vk.DestroyInstance(gVKInstance, NULL);
    gVKDevice = VK_NULL_HANDLE;
    gVKSurface = VK_NULL_HANDLE;
    gVKInstance = VK_NULL_HANDLE;
    gVKGPU = VK_NULL_HANDLE;
    gVKQueue = VK_NULL_HANDLE;
    gVKCoreCreatedDevice = false;
    gVKNegotiation = NULL;
    gVKHasImage = false;
    gVKWaitCount = 0;
    gVKCoreCommandCount = 0;
    gVKSignal = VK_NULL_HANDLE;
}

static void OSLRImageBarrier(VkCommandBuffer command, VkImage image, VkImageLayout from, VkImageLayout to,
                             VkAccessFlags srcAccess, VkAccessFlags dstAccess,
                             VkPipelineStageFlags srcStage, VkPipelineStageFlags dstStage) {
    VkImageMemoryBarrier barrier;
    memset(&barrier, 0, sizeof(barrier));
    barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.srcAccessMask = srcAccess;
    barrier.dstAccessMask = dstAccess;
    barrier.oldLayout = from;
    barrier.newLayout = to;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = image;
    barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    barrier.subresourceRange.levelCount = 1;
    barrier.subresourceRange.layerCount = 1;
    vk.CmdPipelineBarrier(command, srcStage, dstStage, 0, 0, NULL, 0, NULL, 1, &barrier);
}

/// Copia la imagen del núcleo (width × height) a la pantalla y la muestra.
static void OSLRPresentVulkan(unsigned width, unsigned height) {
    if (gVKDevice == VK_NULL_HANDLE || !gVKHasImage || atomic_load(&gBackground)) return;
    if (atomic_exchange(&gMetalLayerChanged, false) || gVKSwapchain == VK_NULL_HANDLE) OSLRCreateSwapchain();
    uint32_t frame = gVKFrame;
    VkCommandBuffer command = gVKCommands[frame];
    VkFence fence = gVKFences[frame];
    vk.WaitForFences(gVKDevice, 1, &fence, VK_TRUE, UINT64_MAX);
    uint32_t imageIndex = 0;
    BOOL haveTarget = NO;
    if (gVKSwapchain != VK_NULL_HANDLE) {
        VkResult acquired = vk.AcquireNextImageKHR(gVKDevice, gVKSwapchain, UINT64_MAX, gVKAcquired[frame], VK_NULL_HANDLE, &imageIndex);
        haveTarget = (acquired == VK_SUCCESS || acquired == VK_SUBOPTIMAL_KHR) && imageIndex < gVKSwapCount;
        if (acquired == VK_ERROR_OUT_OF_DATE_KHR || acquired == VK_SUBOPTIMAL_KHR) atomic_store(&gMetalLayerChanged, true);
    }
    vk.ResetFences(gVKDevice, 1, &fence);
    vk.ResetCommandBuffer(command, 0);
    VkCommandBufferBeginInfo begin;
    memset(&begin, 0, sizeof(begin));
    begin.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vk.BeginCommandBuffer(command, &begin);
    VkImage source = gVKImage.create_info.image;
    VkImageLayout layout = gVKImage.image_layout;
    if (haveTarget && source != VK_NULL_HANDLE) {
        VkImage target = gVKSwapImages[imageIndex];
        OSLRImageBarrier(command, source, layout, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                         VK_ACCESS_MEMORY_WRITE_BIT, VK_ACCESS_TRANSFER_READ_BIT,
                         VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT);
        OSLRImageBarrier(command, target, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                         0, VK_ACCESS_TRANSFER_WRITE_BIT,
                         VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT);
        VkImageBlit region;
        memset(&region, 0, sizeof(region));
        region.srcSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        region.srcSubresource.layerCount = 1;
        region.srcOffsets[1].x = (int32_t)width;
        region.srcOffsets[1].y = (int32_t)height;
        region.srcOffsets[1].z = 1;
        region.dstSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        region.dstSubresource.layerCount = 1;
        region.dstOffsets[1].x = (int32_t)gVKSwapExtent.width;
        region.dstOffsets[1].y = (int32_t)gVKSwapExtent.height;
        region.dstOffsets[1].z = 1;
        vk.CmdBlitImage(command, source, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, target, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                        1, &region, gGLSmooth ? VK_FILTER_LINEAR : VK_FILTER_NEAREST);
        OSLRImageBarrier(command, target, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
                         VK_ACCESS_TRANSFER_WRITE_BIT, 0,
                         VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT);
        OSLRImageBarrier(command, source, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, layout,
                         VK_ACCESS_TRANSFER_READ_BIT, VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT,
                         VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT);
    }
    vk.EndCommandBuffer(command);
    // Primero lo que mandó el núcleo (esperando sus semáforos) y luego la copia.
    VkSubmitInfo submits[2];
    memset(submits, 0, sizeof(submits));
    uint32_t submitCount = 0;
    VkSemaphore ownWaits[OSLR_VK_MAX_WAITS + 1];
    VkPipelineStageFlags ownStages[OSLR_VK_MAX_WAITS + 1];
    uint32_t ownWaitCount = 0;
    if (gVKCoreCommandCount > 0) {
        submits[0].sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submits[0].waitSemaphoreCount = gVKWaitCount;
        submits[0].pWaitSemaphores = gVKWaits;
        submits[0].pWaitDstStageMask = gVKWaitStages;
        submits[0].commandBufferCount = gVKCoreCommandCount;
        submits[0].pCommandBuffers = gVKCoreCommands;
        submitCount = 1;
    } else {
        for (uint32_t index = 0; index < gVKWaitCount; index++) {
            ownWaits[ownWaitCount] = gVKWaits[index];
            ownStages[ownWaitCount] = VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
            ownWaitCount++;
        }
    }
    if (haveTarget) {
        ownWaits[ownWaitCount] = gVKAcquired[frame];
        ownStages[ownWaitCount] = VK_PIPELINE_STAGE_TRANSFER_BIT;
        ownWaitCount++;
    }
    VkSemaphore signals[2];
    uint32_t signalCount = 0;
    if (haveTarget) signals[signalCount++] = gVKRendered[imageIndex];
    if (gVKSignal != VK_NULL_HANDLE) signals[signalCount++] = gVKSignal;
    VkSubmitInfo *own = &submits[submitCount];
    own->sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    own->waitSemaphoreCount = ownWaitCount;
    own->pWaitSemaphores = ownWaits;
    own->pWaitDstStageMask = ownStages;
    own->commandBufferCount = 1;
    own->pCommandBuffers = &command;
    own->signalSemaphoreCount = signalCount;
    own->pSignalSemaphores = signals;
    submitCount++;
    pthread_mutex_lock(&gVKQueueLock);
    VkResult submitted = vk.QueueSubmit(gVKQueue, submitCount, submits, fence);
    if (haveTarget && submitted == VK_SUCCESS) {
        VkPresentInfoKHR present;
        memset(&present, 0, sizeof(present));
        present.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
        present.waitSemaphoreCount = 1;
        present.pWaitSemaphores = &gVKRendered[imageIndex];
        present.swapchainCount = 1;
        present.pSwapchains = &gVKSwapchain;
        present.pImageIndices = &imageIndex;
        VkResult presented = vk.QueuePresentKHR(gVKQueue, &present);
        if (presented == VK_ERROR_OUT_OF_DATE_KHR || presented == VK_SUBOPTIMAL_KHR) atomic_store(&gMetalLayerChanged, true);
    }
    pthread_mutex_unlock(&gVKQueueLock);
    // Los semáforos y comandos de set_image se usan una sola vez.
    gVKWaitCount = 0;
    gVKCoreCommandCount = 0;
    gVKSignal = VK_NULL_HANDLE;
    gVKFrame = (gVKFrame + 1) % OSLR_VK_FRAMES;
    if (haveTarget && !atomic_exchange(&gGLLayerShown, true)) {
        dispatch_async(dispatch_get_main_queue(), ^{ gMetalLayer.hidden = NO; });
    }
}

static bool OSLREnvironment(unsigned command, void *data) {
    switch (command) {
        case RETRO_ENVIRONMENT_SET_HW_RENDER: {
            struct retro_hw_render_callback *callback = data;
            if (callback == NULL) return false;
            enum retro_hw_context_type type = callback->context_type;
            if (type == RETRO_HW_CONTEXT_VULKAN) {
                if (gMetalLayer == nil) return false;
                gHWCallback = *callback;
                gHWRequested = true;
                return true;
            }
            if (gGLLayer == nil) return false;
            BOOL gles = type == RETRO_HW_CONTEXT_OPENGLES2 || type == RETRO_HW_CONTEXT_OPENGLES3 ||
                (type == RETRO_HW_CONTEXT_OPENGLES_VERSION && callback->version_major <= 3);
            if (!gles) return false;
            callback->get_current_framebuffer = OSLRCurrentFramebuffer;
            callback->get_proc_address = OSLRProcAddress;
            gHWCallback = *callback;
            gHWRequested = true;
            return true;
        }
        case RETRO_ENVIRONMENT_GET_PREFERRED_HW_RENDER:
            if (gMetalLayer != nil) {
                if (data) *(unsigned *)data = RETRO_HW_CONTEXT_VULKAN;
                return true;
            }
            if (gGLLayer == nil) return false;
            if (data) *(unsigned *)data = RETRO_HW_CONTEXT_OPENGLES3;
            return true;
        case RETRO_ENVIRONMENT_SET_HW_SHARED_CONTEXT:
            return gGLLayer != nil || gMetalLayer != nil;
        case RETRO_ENVIRONMENT_GET_HW_RENDER_INTERFACE: {
            if (data == NULL || gVKDevice == VK_NULL_HANDLE) return false;
            *(const struct retro_hw_render_interface **)data = (const struct retro_hw_render_interface *)&gVKInterface;
            return true;
        }
        case RETRO_ENVIRONMENT_SET_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE: {
            const struct retro_hw_render_context_negotiation_interface *iface = data;
            if (iface == NULL || iface->interface_type != RETRO_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE_VULKAN) return false;
            gVKNegotiation = (const struct retro_hw_render_context_negotiation_interface_vulkan *)iface;
            return true;
        }
        case RETRO_ENVIRONMENT_GET_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE_SUPPORT: {
            struct retro_hw_render_context_negotiation_interface *iface = data;
            if (iface == NULL || iface->interface_type != RETRO_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE_VULKAN) return false;
            iface->interface_version = RETRO_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE_VULKAN_VERSION;
            return true;
        }
        case RETRO_ENVIRONMENT_SET_DISK_CONTROL_INTERFACE: {
            const struct retro_disk_control_callback *callback = data;
            if (callback == NULL) return false;
            memset(&gDisk, 0, sizeof(gDisk));
            gDisk.set_eject_state = callback->set_eject_state;
            gDisk.get_eject_state = callback->get_eject_state;
            gDisk.get_image_index = callback->get_image_index;
            gDisk.set_image_index = callback->set_image_index;
            gDisk.get_num_images = callback->get_num_images;
            gDisk.replace_image_index = callback->replace_image_index;
            gDisk.add_image_index = callback->add_image_index;
            gHasDisk = true;
            return true;
        }
        case RETRO_ENVIRONMENT_SET_DISK_CONTROL_EXT_INTERFACE: {
            const struct retro_disk_control_ext_callback *callback = data;
            if (callback == NULL) return false;
            gDisk = *callback;
            gHasDisk = true;
            return true;
        }
        case RETRO_ENVIRONMENT_GET_DISK_CONTROL_INTERFACE_VERSION:
            if (data) *(unsigned *)data = 1;
            return true;
        case RETRO_ENVIRONMENT_SET_ROTATION:
            return false;
        case RETRO_ENVIRONMENT_GET_OVERSCAN:
            if (data) *(bool *)data = false;
            return true;
        case RETRO_ENVIRONMENT_GET_CAN_DUPE:
            if (data) *(bool *)data = true;
            return true;
        case RETRO_ENVIRONMENT_SET_MESSAGE: {
            const struct retro_message *message = data;
            if (message) OSLRShowMessage(message->msg);
            return true;
        }
        case RETRO_ENVIRONMENT_SET_MESSAGE_EXT: {
            const struct retro_message_ext *message = data;
            if (message && message->target != RETRO_MESSAGE_TARGET_LOG) OSLRShowMessage(message->msg);
            return true;
        }
        case RETRO_ENVIRONMENT_GET_MESSAGE_INTERFACE_VERSION:
            if (data) *(unsigned *)data = 1;
            return true;
        case RETRO_ENVIRONMENT_SHUTDOWN:
            atomic_store(&gShutdownRequested, true);
            return true;
        case RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL:
            return true;
        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
            if (data) *(const char **)data = gSystemDir;
            return true;
        case RETRO_ENVIRONMENT_GET_CORE_ASSETS_DIRECTORY:
            if (data) *(const char **)data = gSystemDir;
            return true;
        case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
            if (data) *(const char **)data = gSaveDir;
            return true;
        case RETRO_ENVIRONMENT_GET_LIBRETRO_PATH:
            if (data) *(const char **)data = gCorePath;
            return true;
        case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
            if (data == NULL) return false;
            enum retro_pixel_format format = *(const enum retro_pixel_format *)data;
            if (format != RETRO_PIXEL_FORMAT_0RGB1555 && format != RETRO_PIXEL_FORMAT_XRGB8888 && format != RETRO_PIXEL_FORMAT_RGB565) return false;
            gPixelFormat = format;
            return true;
        }
        case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
        case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
        case RETRO_ENVIRONMENT_SET_MEMORY_MAPS:
        case RETRO_ENVIRONMENT_SET_SUPPORT_ACHIEVEMENTS:
        case RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS:
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_DISPLAY:
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_UPDATE_DISPLAY_CALLBACK:
        case RETRO_ENVIRONMENT_SET_CONTENT_INFO_OVERRIDE:
        case RETRO_ENVIRONMENT_SET_MINIMUM_AUDIO_LATENCY:
        case RETRO_ENVIRONMENT_SET_SUBSYSTEM_INFO:
            return true;
        case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
            return true;
        case RETRO_ENVIRONMENT_GET_VARIABLE: {
            struct retro_variable *variable = data;
            if (variable == NULL || variable->key == NULL) return false;
            variable->value = OSLROptionValue(variable->key);
            return variable->value != NULL;
        }
        case RETRO_ENVIRONMENT_SET_VARIABLES:
            if (gCapturing || gRecording) OSLRCaptureVariables(data);
            if (gCapturing) return true;
            OSLRRegisterVariables(data);
            return true;
        case RETRO_ENVIRONMENT_SET_VARIABLE: {
            const struct retro_variable *variable = data;
            if (variable == NULL) return true;
            if (variable->key && variable->value) {
                NSString *key = [NSString stringWithUTF8String:variable->key];
                NSString *value = [NSString stringWithUTF8String:variable->value];
                if (key && value) gDefaultOptions[key] = value;
            }
            return true;
        }
        case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
            if (data) *(bool *)data = atomic_exchange(&gVariablesChanged, false);
            return true;
        case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
            if (data) *(unsigned *)data = 2;
            return true;
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS:
            if (gCapturing || gRecording) OSLRCaptureV1(data, NO);
            if (gCapturing) return true;
            OSLRRegisterV1(data);
            return true;
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL: {
            const struct retro_core_options_intl *options = data;
            if ((gCapturing || gRecording) && options) { OSLRCaptureV1(options->us, NO); OSLRCaptureV1(options->local, YES); }
            if (gCapturing) return true;
            if (options) OSLRRegisterV1(options->us);
            return true;
        }
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2:
            if (gCapturing || gRecording) OSLRCaptureV2(data, NO);
            if (gCapturing) return true;
            OSLRRegisterV2(data);
            return true;
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL: {
            const struct retro_core_options_v2_intl *options = data;
            if ((gCapturing || gRecording) && options) { OSLRCaptureV2(options->us, NO); OSLRCaptureV2(options->local, YES); }
            if (gCapturing) return true;
            if (options) OSLRRegisterV2(options->us);
            return true;
        }
        case RETRO_ENVIRONMENT_SET_FRAME_TIME_CALLBACK: {
            const struct retro_frame_time_callback *callback = data;
            if (callback == NULL) return false;
            gFrameTimeCallback = *callback;
            gHasFrameTimeCallback = callback->callback != NULL;
            return true;
        }
        case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: {
            struct retro_log_callback *log = data;
            if (log == NULL) return false;
            log->log = OSLRLog;
            return true;
        }
        case RETRO_ENVIRONMENT_GET_INPUT_DEVICE_CAPABILITIES:
            if (data) *(uint64_t *)data = (1 << RETRO_DEVICE_JOYPAD) | (1 << RETRO_DEVICE_ANALOG) | (1 << RETRO_DEVICE_POINTER);
            return true;
        case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
            return true;
        case RETRO_ENVIRONMENT_GET_INPUT_MAX_USERS:
            if (data) *(unsigned *)data = 1;
            return true;
        case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO: {
            const struct retro_system_av_info *info = data;
            if (info == NULL) return false;
            OSLRUpdateGeometry(&info->geometry);
            // El ritmo también puede cambiar (el bucle lo lee en cada fotograma).
            if (info->timing.fps > 1) gFPS = info->timing.fps;
            // Más resolución que antes: el framebuffer del núcleo crece.
            if (gGLContext != nil && (info->geometry.max_width > gGLWidth || info->geometry.max_height > gGLHeight)) {
                OSLRResizeGL(MAX(info->geometry.max_width, gGLWidth), MAX(info->geometry.max_height, gGLHeight));
            }
            return true;
        }
        case RETRO_ENVIRONMENT_SET_GEOMETRY:
            OSLRUpdateGeometry(data);
            return true;
        case RETRO_ENVIRONMENT_GET_USERNAME:
            if (data) *(const char **)data = "OmniStation";
            return true;
        case RETRO_ENVIRONMENT_GET_LANGUAGE:
            if (data) *(unsigned *)data = gLanguage;
            return true;
        case RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE:
            if (data) *(int *)data = 3;
            return true;
        case RETRO_ENVIRONMENT_GET_FASTFORWARDING:
            if (data) *(bool *)data = false;
            return true;
        case RETRO_ENVIRONMENT_GET_TARGET_REFRESH_RATE:
            if (data) *(float *)data = 60.0f;
            return true;
        case RETRO_ENVIRONMENT_GET_SAVESTATE_CONTEXT:
            if (data) *(int *)data = 0; // RETRO_SAVESTATE_CONTEXT_NORMAL
            return true;
        case OSLR_RETRO_ENVIRONMENT_EXEC_MEM_ALLOC: {
            struct OSLRExecMemAlloc *request = data;
            if (request == NULL || gCapturing) return false;
            request->rx = NULL;
            request->rw = NULL;
            if (!OSLRUsesJITScript()) {
                // Antes de iOS 26 el JIT del depurador deja que el núcleo se reserve su memoria.
                request->mode = gJITCapable ? OSLR_EXEC_MEM_MODE_UNRESTRICTED : OSLR_EXEC_MEM_MODE_UNAVAILABLE;
                return request->size == 0;
            }
            // El JIT de esta partida: el del bloque permanente (se prepara ahora si hay depurador).
            if (!gJITWanted || !OSLRPrepareJITPool()) {
                OSLRTrace([NSString stringWithFormat:@"JIT permanente: no (%@)", gJITWanted ? (gJITPoolStatus ?: @"?") : @"JIT desactivado"], NO);
                request->mode = OSLR_EXEC_MEM_MODE_UNAVAILABLE;
                return request->size == 0;
            }
            request->mode = OSLR_EXEC_MEM_MODE_DUAL_MAP;
            if (request->size == 0) return true;
            void *rx = OSLRJITPoolAllocate(request->size);
            // Los bloques pequeños (sombreadores de 3DS) son muchos: solo se apuntan los primeros.
            if (rx == NULL || request->size >= (size_t)1024 * 1024 || atomic_fetch_add(&gJITSmallLogged, 1) < 3)
                OSLRTrace([NSString stringWithFormat:@"JIT permanente: %zu KB %@", request->size / 1024, rx ? @"dados" : @"NO caben"], NO);
            if (rx == NULL) return false;
            request->rx = rx;
            request->rw = (uint8_t *)rx + gJITPoolDiff;
            atomic_store(&gJITPoolGiven, true);
            // Puede llegar desde cualquier hilo del núcleo (CPU, sombreadores).
            @synchronized (gJITSessionBlocks) { [gJITSessionBlocks addObject:[NSValue valueWithPointer:rx]]; }
            return true;
        }
        case OSLR_RETRO_ENVIRONMENT_EXEC_MEM_FREE: {
            const struct OSLRExecMemFree *request = data;
            if (request == NULL) return false;
            uint8_t *rx = request->rx;
            if (rx != NULL && gJITPoolRX != NULL && rx >= gJITPoolRX + gJITPoolDiff) rx -= gJITPoolDiff;
            @synchronized (gJITSessionBlocks) { [gJITSessionBlocks removeObject:[NSValue valueWithPointer:rx]]; }
            return OSLRJITPoolFree(rx);
        }
        case RETRO_ENVIRONMENT_GET_JIT_CAPABLE:
            if (data) *(bool *)data = gJITCapable;
            return true;
        default:
            // Lo demás (imagen por GPU, VFS, discos, rumble…) aún no: el núcleo sigue sin ello.
            return false;
    }
}

// MARK: Imagen

static inline uint32_t OSLRFrom565(uint16_t pixel) {
    uint32_t r = (pixel >> 11) & 0x1F, g = (pixel >> 5) & 0x3F, b = pixel & 0x1F;
    r = (r << 3) | (r >> 2);
    g = (g << 2) | (g >> 4);
    b = (b << 3) | (b >> 2);
    return 0xFF000000u | (r << 16) | (g << 8) | b;
}

static inline uint32_t OSLRFrom1555(uint16_t pixel) {
    uint32_t r = (pixel >> 10) & 0x1F, g = (pixel >> 5) & 0x1F, b = pixel & 0x1F;
    r = (r << 3) | (r >> 2);
    g = (g << 3) | (g >> 2);
    b = (b << 3) | (b >> 2);
    return 0xFF000000u | (r << 16) | (g << 8) | b;
}

static void OSLRVideoRefresh(const void *data, unsigned width, unsigned height, size_t pitch) {
    atomic_fetch_add(&gFrameCount, 1);
    if (width == 0 || height == 0) return;
    // Imagen por GPU: ya está en el framebuffer del núcleo; se copia a la pantalla.
    if (data == RETRO_HW_FRAME_BUFFER_VALID) {
        OSLRNoteFrameSize(width, height);
        if (gVKDevice != VK_NULL_HANDLE) {
            OSLRPresentVulkan(width, height);
        } else {
            OSLRPresentGL(width, height);
        }
        return;
    }
    // NULL: el mismo fotograma de antes.
    if (data == NULL) return;
    OSLRNoteFrameSize(width, height);
    size_t needed = (size_t)width * height;
    os_unfair_lock_lock(&gFrameLock);
    if (needed > gFrameCapacity) {
        uint32_t *grown = realloc(gFrame, needed * sizeof(uint32_t));
        if (grown == NULL) {
            os_unfair_lock_unlock(&gFrameLock);
            return;
        }
        gFrame = grown;
        gFrameCapacity = needed;
    }
    const uint8_t *source = data;
    for (unsigned y = 0; y < height; y++) {
        uint32_t *row = gFrame + (size_t)y * width;
        const uint8_t *line = source + (size_t)y * pitch;
        if (gPixelFormat == RETRO_PIXEL_FORMAT_XRGB8888) {
            const uint32_t *pixels = (const uint32_t *)line;
            for (unsigned x = 0; x < width; x++) row[x] = pixels[x] | 0xFF000000u;
        } else if (gPixelFormat == RETRO_PIXEL_FORMAT_RGB565) {
            const uint16_t *pixels = (const uint16_t *)line;
            for (unsigned x = 0; x < width; x++) row[x] = OSLRFrom565(pixels[x]);
        } else {
            const uint16_t *pixels = (const uint16_t *)line;
            for (unsigned x = 0; x < width; x++) row[x] = OSLRFrom1555(pixels[x]);
        }
    }
    gFrameWidth = width;
    gFrameHeight = height;
    os_unfair_lock_unlock(&gFrameLock);
    atomic_fetch_add(&gFrameSerial, 1);
}

/// Imagen del último fotograma (la pide la pantalla). NULL si no hay fotograma nuevo.
static CGImageRef OSLRCopyFrameImage(uint64_t *lastSerial) {
    uint64_t serial = atomic_load(&gFrameSerial);
    if (serial == *lastSerial) return NULL;
    os_unfair_lock_lock(&gFrameLock);
    unsigned width = gFrameWidth, height = gFrameHeight;
    CFDataRef bytes = NULL;
    if (gFrame != NULL && width > 0 && height > 0) {
        bytes = CFDataCreate(NULL, (const UInt8 *)gFrame, (CFIndex)((size_t)width * height * 4));
    }
    os_unfair_lock_unlock(&gFrameLock);
    *lastSerial = serial;
    if (bytes == NULL) return NULL;
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(bytes);
    CFRelease(bytes);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate(width, height, 8, 32, width * 4, space,
                                     kCGBitmapByteOrder32Little | (CGBitmapInfo)kCGImageAlphaNoneSkipFirst,
                                     provider, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    return image;
}

// MARK: Sonido

static void OSLRPushAudio(const int16_t *samples, size_t frames) {
    if (gAudioRing == NULL || samples == NULL) return;
    size_t write = atomic_load_explicit(&gAudioWrite, memory_order_relaxed);
    size_t read = atomic_load_explicit(&gAudioRead, memory_order_acquire);
    size_t space = gAudioCapacity - (write - read);
    if (frames > space) frames = space; // lleno: lo que sobra se pierde
    for (size_t index = 0; index < frames; index++) {
        size_t slot = (write + index) % gAudioCapacity;
        gAudioRing[slot * 2] = samples[index * 2];
        gAudioRing[slot * 2 + 1] = samples[index * 2 + 1];
    }
    atomic_store_explicit(&gAudioWrite, write + frames, memory_order_release);
}

static void OSLRAudioSample(int16_t left, int16_t right) {
    int16_t pair[2] = {left, right};
    OSLRPushAudio(pair, 1);
}

static size_t OSLRAudioSampleBatch(const int16_t *data, size_t frames) {
    OSLRPushAudio(data, frames);
    return frames;
}

/// Lo que queda por sonar, de 0 a 1.
static double OSLRAudioFill(void) {
    if (gAudioCapacity == 0) return 0.5;
    size_t write = atomic_load(&gAudioWrite);
    size_t read = atomic_load(&gAudioRead);
    return (double)(write - read) / (double)gAudioCapacity;
}

// MARK: Mando

static void OSLRInputPoll(void) {}

static int16_t OSLRInputState(unsigned port, unsigned device, unsigned index, unsigned identifier) {
    if (port != 0 || atomic_load(&gInputSuspended)) return 0;
    uint32_t bits = atomic_load(&gPadBits) | atomic_load(&gTouchBits);
    switch (device & RETRO_DEVICE_MASK) {
        case RETRO_DEVICE_JOYPAD:
            if (identifier == RETRO_DEVICE_ID_JOYPAD_MASK) return (int16_t)(bits & 0xFFFF);
            return identifier < 16 ? (int16_t)((bits >> identifier) & 1) : 0;
        case RETRO_DEVICE_ANALOG:
            if (index == RETRO_DEVICE_INDEX_ANALOG_LEFT && atomic_load(&gTouchStickActive)) {
                return (int16_t)atomic_load(&gTouchAxis[identifier == RETRO_DEVICE_ID_ANALOG_Y ? 1 : 0]);
            }
            if (index == RETRO_DEVICE_INDEX_ANALOG_RIGHT) {
                // Botones C táctiles (N64) = stick derecho a tope.
                uint32_t c = atomic_load(&gTouchCBits);
                if (c != 0) {
                    if (identifier == RETRO_DEVICE_ID_ANALOG_X) return (c & 8) ? 0x7FFF : ((c & 4) ? -0x7FFF : 0);
                    return (c & 2) ? 0x7FFF : ((c & 1) ? -0x7FFF : 0);
                }
            }
            if (index == RETRO_DEVICE_INDEX_ANALOG_LEFT || index == RETRO_DEVICE_INDEX_ANALOG_RIGHT) {
                unsigned axis = index * 2 + (identifier == RETRO_DEVICE_ID_ANALOG_Y ? 1 : 0);
                return (int16_t)atomic_load(&gAxis[axis]);
            }
            if (index == RETRO_DEVICE_INDEX_ANALOG_BUTTON && identifier < 16) {
                return ((bits >> identifier) & 1) ? 0x7FFF : 0;
            }
            return 0;
        case RETRO_DEVICE_POINTER:
            if (index != 0) return 0;
            if (identifier == RETRO_DEVICE_ID_POINTER_X) return (int16_t)atomic_load(&gPointerX);
            if (identifier == RETRO_DEVICE_ID_POINTER_Y) return (int16_t)atomic_load(&gPointerY);
            if (identifier == RETRO_DEVICE_ID_POINTER_PRESSED) return atomic_load(&gPointerDown) ? 1 : 0;
            if (identifier == RETRO_DEVICE_ID_POINTER_COUNT) return atomic_load(&gPointerDown) ? 1 : 0;
            return 0;
        default:
            return 0;
    }
}

// MARK: - Botón físico → botón de libretro (posicional, como RetroArch)

/// Id del mapa de botones de OmniStation (a, b, x, y, l1…) → RETRO_DEVICE_ID_JOYPAD_*.
static int OSLRRetroButtonForMapID(NSString *name) {
    static NSDictionary<NSString *, NSNumber *> *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{@"a": @(RETRO_DEVICE_ID_JOYPAD_B), @"b": @(RETRO_DEVICE_ID_JOYPAD_A),
                  @"x": @(RETRO_DEVICE_ID_JOYPAD_Y), @"y": @(RETRO_DEVICE_ID_JOYPAD_X),
                  @"l1": @(RETRO_DEVICE_ID_JOYPAD_L), @"r1": @(RETRO_DEVICE_ID_JOYPAD_R),
                  @"l2": @(RETRO_DEVICE_ID_JOYPAD_L2), @"r2": @(RETRO_DEVICE_ID_JOYPAD_R2),
                  @"l3": @(RETRO_DEVICE_ID_JOYPAD_L3), @"r3": @(RETRO_DEVICE_ID_JOYPAD_R3),
                  @"menu": @(RETRO_DEVICE_ID_JOYPAD_START), @"options": @(RETRO_DEVICE_ID_JOYPAD_SELECT)};
    });
    NSNumber *value = table[name];
    return value ? value.intValue : -1;
}

// MARK: - Vistas

/// Contenedor del mando táctil: lo que no es un botón deja pasar el toque (a la pantalla del juego).
@interface OSLRPassThroughView : UIView
@end

@implementation OSLRPassThroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

/// Pantalla del juego. En los sistemas con pantalla táctil (NDS), los toques hacen de lápiz.
@interface OSLRVideoView : UIView
@property (nonatomic, assign) BOOL pointerEnabled;
/// Capa de OpenGL ES (núcleos con imagen por GPU). Oculta hasta el primer fotograma.
@property (nonatomic, strong, nullable) CAEAGLLayer *glLayer;
/// Capa de Metal (núcleos con Vulkan, por MoltenVK). Oculta hasta el primer fotograma.
@property (nonatomic, strong, nullable) CAMetalLayer *metalLayer;
- (void)enableGLLayer;
- (void)enableMetalLayer;
@end

@implementation OSLRVideoView {
    UITouch *_pointerTouch;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.blackColor;
        self.layer.contentsGravity = kCAGravityResize;
        self.layer.magnificationFilter = kCAFilterNearest;
        self.multipleTouchEnabled = NO;
    }
    return self;
}

- (void)enableGLLayer {
    if (self.glLayer != nil) return;
    CAEAGLLayer *layer = [CAEAGLLayer layer];
    layer.opaque = YES;
    layer.hidden = YES;
    layer.contentsScale = UIScreen.mainScreen.nativeScale;
    layer.drawableProperties = @{kEAGLDrawablePropertyRetainedBacking: @NO,
                                 kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8};
    layer.frame = self.bounds;
    [self.layer addSublayer:layer];
    self.glLayer = layer;
}

- (void)enableMetalLayer {
    if (self.metalLayer != nil) return;
    CAMetalLayer *layer = [CAMetalLayer layer];
    layer.opaque = YES;
    layer.hidden = YES;
    layer.contentsScale = UIScreen.mainScreen.nativeScale;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.frame = self.bounds;
    [self.layer addSublayer:layer];
    self.metalLayer = layer;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.glLayer == nil && self.metalLayer == nil) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (self.glLayer) self.glLayer.frame = self.bounds;
    if (self.metalLayer) {
        self.metalLayer.frame = self.bounds;
        CGFloat scale = self.metalLayer.contentsScale;
        self.metalLayer.drawableSize = CGSizeMake(MAX(1, self.bounds.size.width * scale), MAX(1, self.bounds.size.height * scale));
    }
    [CATransaction commit];
    atomic_store(&gGLLayerChanged, true);
    atomic_store(&gMetalLayerChanged, true);
}

- (void)updatePointer:(UITouch *)touch {
    CGSize size = self.bounds.size;
    if (size.width < 1 || size.height < 1) return;
    CGPoint point = [touch locationInView:self];
    double x = MAX(0, MIN(1, point.x / size.width)) * 2.0 - 1.0;
    double y = MAX(0, MIN(1, point.y / size.height)) * 2.0 - 1.0;
    atomic_store(&gPointerX, (int32_t)(x * 0x7FFF));
    atomic_store(&gPointerY, (int32_t)(y * 0x7FFF));
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.pointerEnabled || _pointerTouch != nil) return;
    _pointerTouch = touches.anyObject;
    [self updatePointer:_pointerTouch];
    atomic_store(&gPointerDown, true);
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_pointerTouch && [touches containsObject:_pointerTouch]) [self updatePointer:_pointerTouch];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_pointerTouch && [touches containsObject:_pointerTouch]) {
        _pointerTouch = nil;
        atomic_store(&gPointerDown, false);
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}
@end

/// Stick analógico táctil (izquierdo).
@interface OSLRStickView : UIView
@end

@implementation OSLRStickView {
    UIView *_knob;
    UITouch *_touch;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.30];
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.40].CGColor;
        self.multipleTouchEnabled = NO;
        _knob = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 50, 50)];
        _knob.backgroundColor = [UIColor colorWithWhite:1 alpha:0.35];
        _knob.layer.cornerRadius = 25;
        _knob.userInteractionEnabled = NO;
        [self addSubview:_knob];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = self.bounds.size.width * 0.5;
    if (_touch == nil) _knob.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
}

- (void)track:(UITouch *)touch {
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGPoint point = [touch locationInView:self];
    CGFloat radius = MAX(1, self.bounds.size.width * 0.5 - 12);
    CGFloat dx = point.x - center.x, dy = point.y - center.y;
    CGFloat length = sqrt(dx * dx + dy * dy);
    if (length > radius) {
        dx = dx / length * radius;
        dy = dy / length * radius;
    }
    _knob.center = CGPointMake(center.x + dx, center.y + dy);
    atomic_store(&gTouchAxis[0], (int32_t)(dx / radius * 32767.0));
    atomic_store(&gTouchAxis[1], (int32_t)(dy / radius * 32767.0));
    atomic_store(&gTouchStickActive, true);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_touch != nil) return;
    _touch = touches.anyObject;
    [self track:_touch];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_touch && [touches containsObject:_touch]) [self track:_touch];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_touch == nil || ![touches containsObject:_touch]) return;
    _touch = nil;
    atomic_store(&gTouchStickActive, false);
    atomic_store(&gTouchAxis[0], 0);
    atomic_store(&gTouchAxis[1], 0);
    [self setNeedsLayout];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}
@end

// MARK: - Pantalla de juego

// MARK: Estilo de la app en los menús de la partida (como los ajustes de OmniStation)

/// Orbitron (la letra de la app; la registra OmniStation al abrirse), algo más pequeña como allí.
static UIFont *OSLRAppFont(CGFloat size, UIFontWeight weight) {
    NSString *name = weight >= UIFontWeightBold ? @"Orbitron-Bold"
        : (weight >= UIFontWeightSemibold ? @"Orbitron-SemiBold"
        : (weight >= UIFontWeightMedium ? @"Orbitron-Medium" : @"Orbitron-Regular"));
    return [UIFont fontWithName:name size:round(size * 0.88)] ?: [UIFont systemFontOfSize:size weight:weight];
}

static UIColor *OSLRCyan(CGFloat alpha) { return [UIColor colorWithRed:0.0 green:0.85 blue:1.0 alpha:alpha]; }

/// Fondo de panel de la app: azul noche con brillo cian arriba y violeta abajo.
static void OSLRApplyPanelBackground(UIView *view, CGFloat cornerRadius) {
    view.backgroundColor = [UIColor colorWithRed:0.02 green:0.04 blue:0.09 alpha:0.94];
    view.layer.cornerRadius = cornerRadius;
    view.layer.masksToBounds = NO;
    view.layer.borderWidth = 0.8;
    view.layer.borderColor = OSLRCyan(0.40).CGColor;
    view.layer.shadowColor = OSLRCyan(1).CGColor;
    view.layer.shadowOpacity = 0.30;
    view.layer.shadowRadius = 20;
    view.layer.shadowOffset = CGSizeZero;
    for (CALayer *layer in [view.layer.sublayers copy]) {
        if ([layer.name isEqualToString:@"omni.glow"]) [layer removeFromSuperlayer];
    }
    NSArray *glows = @[@[OSLRCyan(0.22), [NSValue valueWithCGPoint:CGPointMake(0, 0)]],
                       @[[UIColor colorWithRed:0.55 green:0.42 blue:1.0 alpha:0.18], [NSValue valueWithCGPoint:CGPointMake(1, 1)]]];
    for (NSArray *glow in glows) {
        CAGradientLayer *layer = [CAGradientLayer layer];
        layer.name = @"omni.glow";
        layer.type = kCAGradientLayerRadial;
        layer.colors = @[(id)((UIColor *)glow[0]).CGColor, (id)UIColor.clearColor.CGColor];
        CGPoint center = [glow[1] CGPointValue];
        layer.startPoint = center;
        layer.endPoint = CGPointMake(center.x == 0 ? 0.9 : 0.1, center.y == 0 ? 0.7 : 0.3);
        layer.cornerRadius = cornerRadius;
        layer.masksToBounds = YES;
        [view.layer insertSublayer:layer atIndex:0];
    }
}

/// Las capas de brillo siguen el tamaño del panel.
static void OSLRLayoutPanelBackground(UIView *view) {
    for (CALayer *layer in view.layer.sublayers) {
        if ([layer.name isEqualToString:@"omni.glow"]) layer.frame = view.bounds;
    }
}

/// Fila como las tarjetas de la app: cristal oscuro con borde de luz; la marcada, iluminada.
static void OSLRStyleRow(UIView *row, BOOL selected) {
    row.layer.cornerRadius = 14;
    row.layer.borderWidth = selected ? 2.0 : 0.8;
    row.layer.borderColor = selected ? OSLRCyan(1).CGColor : OSLRCyan(0.22).CGColor;
    row.backgroundColor = selected ? OSLRCyan(0.20) : [UIColor colorWithWhite:1 alpha:0.07];
    row.layer.shadowColor = OSLRCyan(1).CGColor;
    row.layer.shadowOpacity = selected ? 0.55 : 0;
    row.layer.shadowRadius = 8;
    row.layer.shadowOffset = CGSizeZero;
}

@interface OSLRGameViewController : UIViewController
@property (nonatomic, copy) NSString *language;
@property (nonatomic, copy) NSString *layout;
@property (nonatomic, assign) BOOL touchAlways;
@property (nonatomic, assign) BOOL touchHaptics;
@property (nonatomic, assign) BOOL stretch;
@property (nonatomic, assign) BOOL smooth;
@property (nonatomic, assign) BOOL pointer;
@property (nonatomic, assign) BOOL closing;
/// Cómo arrancó el JIT («JIT activo», «Sin JIT…»); vacío si el núcleo no tiene esa opción.
@property (nonatomic, copy) NSString *jitText;
@property (nonatomic, assign) BOOL jitOn;
@property (nonatomic, strong, nullable) OSPerfHUD *hud;
@property (nonatomic, strong, readonly) OSLRVideoView *videoView;
@property (nonatomic, copy, nullable) void (^menuChanged)(BOOL open);
@property (nonatomic, copy, nullable) void (^menuAction)(NSInteger action);
/// Opciones del núcleo que se pueden cambiar en la partida («key», «title», «group», «values», «value»).
@property (nonatomic, strong) NSArray<NSMutableDictionary<NSString *, id> *> *coreOptions;
@property (nonatomic, copy, nullable) void (^optionChanged)(NSString *key, NSString *value);
/// Mapa de botones del juego: botón físico (RETRO id) → el que manda.
@property (nonatomic, copy) NSDictionary<NSNumber *, NSNumber *> *buttonMap;
- (void)showStatus:(NSString *)message;
- (void)reloadCoreOptions:(NSArray<NSMutableDictionary<NSString *, id> *> *)options;
- (void)openMenu;
- (void)closeMenu;
- (void)releaseExternalDisplay;
@end

typedef NS_ENUM(NSInteger, OSLRMenuAction) {
    OSLRMenuActionResume = 0,
    OSLRMenuActionSaveState,
    OSLRMenuActionLoadState,
    OSLRMenuActionReset,
    OSLRMenuActionQuit,
    OSLRMenuActionDisc,
    OSLRMenuActionOptions
};

@implementation OSLRGameViewController {
    OSLRPassThroughView *_controlsView;
    NSMutableArray<UIView *> *_groups;
    UIButton *_menuButton;
    UILabel *_statusLabel;
    UILabel *_tvLabel;
    UIView *_menuView;
    NSArray<UIButton *> *_menuRows;
    NSArray<UIButton *> *_visibleRows;
    UILabel *_jitLabel;
    // Opciones del núcleo (una página del menú).
    UIView *_optionsView;
    UILabel *_optionsTitle;
    UILabel *_optionsHint;
    UIScrollView *_optionsScroll;
    NSMutableArray<UIButton *> *_optionRows;
    NSMutableArray<UILabel *> *_optionHeaders;
    BOOL _optionsVisible;
    NSInteger _optionIndex;
    BOOL _prevLeft, _prevRight;
    NSInteger _menuIndex;
    BOOL _menuVisible;
    CADisplayLink *_displayLink;
    uint64_t _lastSerial;
    NSUInteger _statusToken;
    BOOL _prevHome, _prevCombo, _prevUp, _prevDown, _prevA, _prevB;
    NSMutableArray<id> *_observers;
    UIImpactFeedbackGenerator *_haptic;
    UIView *_tvHost;
    BOOL _onTV;
    GCController *_controller;
    uint32_t _physicalBits;
    double _hudTime;
    uint64_t _hudFrames;
}

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        _language = @"es";
        _layout = @"snes";
        _observers = [NSMutableArray new];
        _groups = [NSMutableArray new];
        _buttonMap = @{};
        _coreOptions = @[];
        _videoView = [[OSLRVideoView alloc] initWithFrame:CGRectMake(0, 0, 4, 3)];
    }
    return self;
}

- (NSString *)t:(NSString *)spanish en:(NSString *)english {
    return OSLRText(self.language, spanish, english);
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures { return UIRectEdgeAll; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAllButUpsideDown; }

// MARK: Botones táctiles

- (UIButton *)padButton:(NSString *)title retroID:(NSInteger)retroID {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.tag = retroID;
    button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.42];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithRed:0.4 green:0.9 blue:1.0 alpha:1.0] forState:UIControlStateHighlighted];
    button.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.40].CGColor;
    button.layer.cornerRadius = 19;
    button.exclusiveTouch = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self action:@selector(padDown:) forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(padUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    return button;
}

- (void)padDown:(UIButton *)sender {
    if (sender.tag >= 100) {
        atomic_fetch_or(&gTouchCBits, 1u << (uint32_t)(sender.tag - 100));
    } else {
        atomic_fetch_or(&gTouchBits, 1u << (uint32_t)sender.tag);
    }
    if (self.touchHaptics) [_haptic impactOccurred];
}

- (void)padUp:(UIButton *)sender {
    if (sender.tag >= 100) {
        atomic_fetch_and(&gTouchCBits, ~(1u << (uint32_t)(sender.tag - 100)));
    } else {
        atomic_fetch_and(&gTouchBits, ~(1u << (uint32_t)sender.tag));
    }
}

/// Cruz de 4 botones (arriba, abajo, izquierda, derecha).
- (UIView *)crossWithTitles:(NSArray<NSString *> *)titles ids:(NSArray<NSNumber *> *)ids tag:(NSInteger)tag {
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 112, 112)];
    pad.tag = tag;
    CGRect frames[4] = {CGRectMake(37, 0, 38, 38), CGRectMake(37, 74, 38, 38), CGRectMake(0, 37, 38, 38), CGRectMake(74, 37, 38, 38)};
    for (NSUInteger index = 0; index < 4; index++) {
        if (ids[index].integerValue < 0) continue;
        UIButton *button = [self padButton:titles[index] retroID:ids[index].integerValue];
        button.frame = frames[index];
        [pad addSubview:button];
    }
    return pad;
}

- (UIView *)pairWithFirst:(NSString *)first firstID:(NSInteger)firstID second:(nullable NSString *)second secondID:(NSInteger)secondID tag:(NSInteger)tag {
    UIView *pair = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 108, 40)];
    pair.tag = tag;
    UIButton *a = [self padButton:first retroID:firstID];
    a.frame = second ? CGRectMake(0, 0, 50, 40) : CGRectMake(0, 0, 108, 40);
    a.layer.cornerRadius = 12;
    [pair addSubview:a];
    if (second) {
        UIButton *b = [self padButton:second retroID:secondID];
        b.frame = CGRectMake(58, 0, 50, 40);
        b.layer.cornerRadius = 12;
        [pair addSubview:b];
    }
    return pair;
}

/// Dos botones redondos (izquierda abajo y derecha arriba), como en NES, Game Boy o N64.
- (UIView *)twoButtonsLeft:(NSString *)leftTitle leftID:(NSInteger)leftID right:(NSString *)rightTitle rightID:(NSInteger)rightID {
    UIView *face = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 112, 112)];
    face.tag = 1002;
    UIButton *left = [self padButton:leftTitle retroID:leftID];
    UIButton *right = [self padButton:rightTitle retroID:rightID];
    left.frame = CGRectMake(2, 50, 50, 50);
    right.frame = CGRectMake(60, 20, 50, 50);
    left.layer.cornerRadius = 25;
    right.layer.cornerRadius = 25;
    [face addSubview:left];
    [face addSubview:right];
    return face;
}

- (void)buildControls {
    NSString *layout = self.layout;
    BOOL playStation = [layout isEqualToString:@"ps1"] || [layout isEqualToString:@"psp"];
    BOOL n64 = [layout isEqualToString:@"n64"];
    BOOL dreamcast = [layout isEqualToString:@"dc"];
    BOOL n3ds = [layout isEqualToString:@"3ds"];
    BOOL gamecube = [layout isEqualToString:@"gc"] || [layout isEqualToString:@"wii"];
    BOOL fourFace = [layout isEqualToString:@"snes"] || [layout isEqualToString:@"nds"] || n3ds;
    BOOL stick = n64 || dreamcast || n3ds || gamecube || [layout isEqualToString:@"psp"];
    if (!n64) {
        UIView *dpad = [self crossWithTitles:@[@"▲", @"▼", @"◀", @"▶"]
                                         ids:@[@(RETRO_DEVICE_ID_JOYPAD_UP), @(RETRO_DEVICE_ID_JOYPAD_DOWN), @(RETRO_DEVICE_ID_JOYPAD_LEFT), @(RETRO_DEVICE_ID_JOYPAD_RIGHT)]
                                         tag:1001];
        [_groups addObject:dpad];
    }
    UIView *face;
    if (fourFace) {
        // Como en el mando de SNES/DS: X arriba, B abajo, Y izquierda, A derecha.
        face = [self crossWithTitles:@[@"X", @"B", @"Y", @"A"]
                                 ids:@[@(RETRO_DEVICE_ID_JOYPAD_X), @(RETRO_DEVICE_ID_JOYPAD_B), @(RETRO_DEVICE_ID_JOYPAD_Y), @(RETRO_DEVICE_ID_JOYPAD_A)]
                                 tag:1002];
    } else if (playStation) {
        // △ arriba, ✕ abajo, □ izquierda, ○ derecha (en libretro: X, B, Y, A).
        face = [self crossWithTitles:@[@"△", @"✕", @"□", @"○"]
                                 ids:@[@(RETRO_DEVICE_ID_JOYPAD_X), @(RETRO_DEVICE_ID_JOYPAD_B), @(RETRO_DEVICE_ID_JOYPAD_Y), @(RETRO_DEVICE_ID_JOYPAD_A)]
                                 tag:1002];
    } else if (gamecube) {
        // Como en el mando de GameCube: Y arriba, A abajo, B izquierda, X derecha.
        face = [self crossWithTitles:@[@"Y", @"A", @"B", @"X"]
                                 ids:@[@(RETRO_DEVICE_ID_JOYPAD_X), @(RETRO_DEVICE_ID_JOYPAD_B), @(RETRO_DEVICE_ID_JOYPAD_Y), @(RETRO_DEVICE_ID_JOYPAD_A)]
                                 tag:1002];
    } else if (dreamcast) {
        // Y arriba, A abajo, X izquierda, B derecha.
        face = [self crossWithTitles:@[@"Y", @"A", @"X", @"B"]
                                 ids:@[@(RETRO_DEVICE_ID_JOYPAD_X), @(RETRO_DEVICE_ID_JOYPAD_B), @(RETRO_DEVICE_ID_JOYPAD_Y), @(RETRO_DEVICE_ID_JOYPAD_A)]
                                 tag:1002];
    } else if (n64) {
        // A y B de N64 (en libretro: B e Y).
        face = [self twoButtonsLeft:@"B" leftID:RETRO_DEVICE_ID_JOYPAD_Y right:@"A" rightID:RETRO_DEVICE_ID_JOYPAD_B];
    } else {
        face = [self twoButtonsLeft:@"B" leftID:RETRO_DEVICE_ID_JOYPAD_B right:@"A" rightID:RETRO_DEVICE_ID_JOYPAD_A];
    }
    [_groups addObject:face];
    if (stick) {
        OSLRStickView *pad = [[OSLRStickView alloc] initWithFrame:CGRectMake(0, 0, 120, 120)];
        pad.tag = 1003;
        [_groups addObject:pad];
    }
    if (n64) {
        // Botones C (el stick derecho).
        [_groups addObject:[self crossWithTitles:@[@"C▲", @"C▼", @"C◀", @"C▶"] ids:@[@100, @101, @102, @103] tag:1004]];
    }
    if ([layout isEqualToString:@"ps1"]) {
        [_groups addObject:[self pairWithFirst:@"L1" firstID:RETRO_DEVICE_ID_JOYPAD_L second:@"L2" secondID:RETRO_DEVICE_ID_JOYPAD_L2 tag:1005]];
        [_groups addObject:[self pairWithFirst:@"R2" firstID:RETRO_DEVICE_ID_JOYPAD_R2 second:@"R1" secondID:RETRO_DEVICE_ID_JOYPAD_R tag:1006]];
    } else if (n64) {
        [_groups addObject:[self pairWithFirst:@"L" firstID:RETRO_DEVICE_ID_JOYPAD_L second:@"Z" secondID:RETRO_DEVICE_ID_JOYPAD_L2 tag:1005]];
        [_groups addObject:[self pairWithFirst:@"R" firstID:RETRO_DEVICE_ID_JOYPAD_R second:nil secondID:-1 tag:1006]];
    } else if (n3ds) {
        [_groups addObject:[self pairWithFirst:@"L" firstID:RETRO_DEVICE_ID_JOYPAD_L second:@"ZL" secondID:RETRO_DEVICE_ID_JOYPAD_L2 tag:1005]];
        [_groups addObject:[self pairWithFirst:@"ZR" firstID:RETRO_DEVICE_ID_JOYPAD_R2 second:@"R" secondID:RETRO_DEVICE_ID_JOYPAD_R tag:1006]];
    } else if (gamecube) {
        // Gatillos L y R (en libretro: L2 y R2) y Z (R).
        [_groups addObject:[self pairWithFirst:@"L" firstID:RETRO_DEVICE_ID_JOYPAD_L2 second:nil secondID:-1 tag:1005]];
        [_groups addObject:[self pairWithFirst:@"Z" firstID:RETRO_DEVICE_ID_JOYPAD_R second:@"R" secondID:RETRO_DEVICE_ID_JOYPAD_R2 tag:1006]];
    } else if (dreamcast) {
        // Gatillos L y R (en libretro: L2 y R2).
        [_groups addObject:[self pairWithFirst:@"L" firstID:RETRO_DEVICE_ID_JOYPAD_L2 second:nil secondID:-1 tag:1005]];
        [_groups addObject:[self pairWithFirst:@"R" firstID:RETRO_DEVICE_ID_JOYPAD_R2 second:nil secondID:-1 tag:1006]];
    } else if (fourFace || [layout isEqualToString:@"gba"] || [layout isEqualToString:@"psp"]) {
        [_groups addObject:[self pairWithFirst:@"L" firstID:RETRO_DEVICE_ID_JOYPAD_L second:nil secondID:-1 tag:1005]];
        [_groups addObject:[self pairWithFirst:@"R" firstID:RETRO_DEVICE_ID_JOYPAD_R second:nil secondID:-1 tag:1006]];
    }
    UIButton *start = [self padButton:@"START" retroID:RETRO_DEVICE_ID_JOYPAD_START];
    start.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    start.layer.cornerRadius = 12;
    UIView *center = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 168, 34)];
    center.tag = 1007;
    if (n64 || dreamcast || gamecube) {
        // Solo START.
        start.frame = CGRectMake(46, 0, 76, 34);
    } else {
        UIButton *select = [self padButton:@"SELECT" retroID:RETRO_DEVICE_ID_JOYPAD_SELECT];
        select.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
        select.layer.cornerRadius = 12;
        select.frame = CGRectMake(0, 0, 76, 34);
        start.frame = CGRectMake(92, 0, 76, 34);
        [center addSubview:select];
    }
    [center addSubview:start];
    [_groups addObject:center];
    for (UIView *group in _groups) {
        group.multipleTouchEnabled = YES;
        [_controlsView addSubview:group];
    }
}

- (void)updateControlsVisibility {
    BOOL physical = GCController.current.extendedGamepad != nil;
    if (!physical) {
        for (GCController *controller in GCController.controllers) {
            if (controller.extendedGamepad != nil) { physical = YES; break; }
        }
    }
    BOOL show = !_onTV ? (self.touchAlways || !physical) : !physical;
    _controlsView.hidden = !show;
    if (!show) {
        atomic_store(&gTouchBits, 0);
        atomic_store(&gTouchCBits, 0);
        atomic_store(&gTouchStickActive, false);
    }
}

// MARK: Vista

- (void)loadView {
    UIView *root = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    root.backgroundColor = UIColor.blackColor;
    self.view = root;
    self.videoView.layer.magnificationFilter = self.smooth ? kCAFilterLinear : kCAFilterNearest;
    self.videoView.pointerEnabled = self.pointer;
    [root addSubview:self.videoView];

    _tvLabel = [UILabel new];
    _tvLabel.text = [self t:@"Jugando en la tele" en:@"Playing on the TV"];
    _tvLabel.textColor = [UIColor colorWithWhite:1 alpha:0.55];
    _tvLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _tvLabel.textAlignment = NSTextAlignmentCenter;
    _tvLabel.hidden = YES;
    _tvLabel.userInteractionEnabled = NO;
    [root addSubview:_tvLabel];

    _controlsView = [[OSLRPassThroughView alloc] initWithFrame:root.bounds];
    _controlsView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _controlsView.backgroundColor = UIColor.clearColor;
    _controlsView.multipleTouchEnabled = YES;
    [root addSubview:_controlsView];
    [self buildControls];

    if (self.hud) {
        [root addSubview:self.hud];
        [self.hud refreshWithFPS:-1 frameTime:0 fifo:0];
    }
    if (self.touchHaptics) {
        _haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [_haptic prepare];
    }

    _menuButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _menuButton.tintColor = UIColor.whiteColor;
    _menuButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    _menuButton.layer.cornerRadius = 20;
    [_menuButton setImage:[UIImage systemImageNamed:@"line.3.horizontal"] forState:UIControlStateNormal];
    [_menuButton addTarget:self action:@selector(openMenu) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_menuButton];

    _statusLabel = [UILabel new];
    _statusLabel.textColor = UIColor.whiteColor;
    _statusLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    _statusLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.numberOfLines = 3;
    _statusLabel.layer.cornerRadius = 10;
    _statusLabel.clipsToBounds = YES;
    _statusLabel.alpha = 0;
    _statusLabel.userInteractionEnabled = NO;
    [root addSubview:_statusLabel];

    [self buildMenu];
    [self updateControlsVisibility];
}

- (void)updateJITLabel {
    _jitLabel.hidden = self.jitText.length == 0;
    if (self.jitText.length > 0) {
        UIColor *color = self.jitOn ? [UIColor colorWithRed:0.30 green:0.95 blue:0.45 alpha:1.0] : [UIColor colorWithRed:1.0 green:0.42 blue:0.38 alpha:1.0];
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightBold];
        UIImage *symbol = [[UIImage systemImageNamed:self.jitOn ? @"bolt.fill" : @"bolt.slash.fill" withConfiguration:config] imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
        NSMutableAttributedString *text = [NSMutableAttributedString new];
        if (symbol) {
            NSTextAttachment *attachment = [NSTextAttachment new];
            attachment.image = symbol;
            [text appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
            [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"  "]];
        }
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:self.jitText attributes:@{
            NSForegroundColorAttributeName: color,
            NSFontAttributeName: OSLRAppFont(14, UIFontWeightBold)}]];
        _jitLabel.attributedText = text;
    }
}

- (void)buildMenu {
    _menuView = [[UIView alloc] initWithFrame:self.view.bounds];
    _menuView.backgroundColor = [UIColor colorWithRed:0.01 green:0.02 blue:0.05 alpha:0.80];
    _menuView.hidden = YES;
    // Si el núcleo puede ir con o sin JIT, arriba se ve cómo arrancó.
    _jitLabel = [UILabel new];
    _jitLabel.textAlignment = NSTextAlignmentCenter;
    _jitLabel.numberOfLines = 2;
    [self updateJITLabel];
    [_menuView addSubview:_jitLabel];
    NSArray<NSString *> *titles = @[[self t:@"Continuar" en:@"Resume"],
                                    [self t:@"Guardar estado" en:@"Save state"],
                                    [self t:@"Cargar estado" en:@"Load state"],
                                    [self t:@"Reiniciar" en:@"Reset"],
                                    [self t:@"Cambiar de disco" en:@"Change disc"],
                                    [self t:@"Opciones del núcleo" en:@"Core options"],
                                    [self t:@"Salir del juego" en:@"Quit game"]];
    NSArray<NSNumber *> *actions = @[@(OSLRMenuActionResume), @(OSLRMenuActionSaveState), @(OSLRMenuActionLoadState),
                                     @(OSLRMenuActionReset), @(OSLRMenuActionDisc), @(OSLRMenuActionOptions), @(OSLRMenuActionQuit)];
    NSMutableArray<UIButton *> *rows = [NSMutableArray new];
    for (NSUInteger index = 0; index < titles.count; index++) {
        UIButton *row = [UIButton buttonWithType:UIButtonTypeSystem];
        row.tag = actions[index].integerValue;
        OSLRStyleRow(row, NO);
        row.titleLabel.font = OSLRAppFont(16, UIFontWeightSemibold);
        [row setTitle:titles[index] forState:UIControlStateNormal];
        UIColor *color = row.tag == OSLRMenuActionQuit ? [UIColor colorWithRed:1.0 green:0.55 blue:0.45 alpha:1.0] : UIColor.whiteColor;
        [row setTitleColor:color forState:UIControlStateNormal];
        [row addTarget:self action:@selector(menuRowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_menuView addSubview:row];
        [rows addObject:row];
    }
    _menuRows = rows;
    [self updateVisibleRows];
    [self.view addSubview:_menuView];
    [self buildOptionsPage];
}

// MARK: Opciones del núcleo en la partida

- (void)buildOptionsPage {
    _optionsView = [[UIView alloc] initWithFrame:CGRectZero];
    OSLRApplyPanelBackground(_optionsView, 22);
    _optionsView.hidden = YES;
    _optionsTitle = [UILabel new];
    _optionsTitle.text = [self t:@"Opciones del núcleo" en:@"Core options"];
    _optionsTitle.textColor = UIColor.whiteColor;
    _optionsTitle.font = OSLRAppFont(18, UIFontWeightBold);
    [_optionsView addSubview:_optionsTitle];
    _optionsHint = [UILabel new];
    _optionsHint.text = [self t:@"‹ › o toca para cambiar · B para volver. Algunas se notan al volver a abrir el juego."
                             en:@"‹ › or tap to change · B to go back. Some apply when the game is opened again."];
    _optionsHint.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    _optionsHint.font = OSLRAppFont(11, UIFontWeightMedium);
    _optionsHint.numberOfLines = 2;
    [_optionsView addSubview:_optionsHint];
    UIButton *back = [UIButton buttonWithType:UIButtonTypeSystem];
    back.tag = 900077;
    [back setImage:[UIImage systemImageNamed:@"chevron.backward.circle.fill"] forState:UIControlStateNormal];
    back.tintColor = [UIColor colorWithRed:0.0 green:0.85 blue:1.0 alpha:1.0];
    [back addTarget:self action:@selector(closeOptionsPage) forControlEvents:UIControlEventTouchUpInside];
    [_optionsView addSubview:back];
    _optionsScroll = [UIScrollView new];
    _optionsScroll.showsVerticalScrollIndicator = YES;
    _optionsScroll.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [_optionsView addSubview:_optionsScroll];
    _optionRows = [NSMutableArray new];
    _optionHeaders = [NSMutableArray new];
    NSString *lastGroup = nil;
    for (NSUInteger index = 0; index < self.coreOptions.count; index++) {
        NSDictionary<NSString *, id> *option = self.coreOptions[index];
        NSString *group = [option[@"group"] isKindOfClass:NSString.class] ? option[@"group"] : @"";
        if (group.length > 0 && ![group isEqualToString:lastGroup]) {
            UILabel *header = [UILabel new];
            header.text = [@"▍ " stringByAppendingString:group.uppercaseString];
            header.textColor = OSLRCyan(0.9);
            header.font = OSLRAppFont(11, UIFontWeightBold);
            header.layer.shadowColor = OSLRCyan(1).CGColor;
            header.layer.shadowOpacity = 0.6;
            header.layer.shadowRadius = 4;
            header.layer.shadowOffset = CGSizeZero;
            header.tag = (NSInteger)index; // fila que va debajo
            [_optionsScroll addSubview:header];
            [_optionHeaders addObject:header];
        }
        lastGroup = group;
        UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
        row.tag = (NSInteger)index;
        OSLRStyleRow(row, NO);
        UILabel *title = [UILabel new];
        title.tag = 900001;
        title.textColor = UIColor.whiteColor;
        title.font = OSLRAppFont(14, UIFontWeightSemibold);
        title.text = option[@"title"];
        title.adjustsFontSizeToFitWidth = YES;
        title.minimumScaleFactor = 0.75;
        [row addSubview:title];
        UILabel *value = [UILabel new];
        value.tag = 900002;
        value.textAlignment = NSTextAlignmentRight;
        value.textColor = [UIColor colorWithRed:0.0 green:0.85 blue:1.0 alpha:1.0];
        value.font = OSLRAppFont(13, UIFontWeightBold);
        value.adjustsFontSizeToFitWidth = YES;
        value.minimumScaleFactor = 0.7;
        [row addSubview:value];
        [row addTarget:self action:@selector(optionRowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_optionsScroll addSubview:row];
        [_optionRows addObject:row];
        [self updateOptionRow:row];
    }
    [self.view addSubview:_optionsView];
}

- (void)reloadCoreOptions:(NSArray<NSMutableDictionary<NSString *, id> *> *)options {
    if (_optionsVisible) return;
    self.coreOptions = options;
    [_optionsView removeFromSuperview];
    _optionsView = nil;
    [self buildOptionsPage];
    [self updateVisibleRows];
    [self.view setNeedsLayout];
}

- (NSString *)labelForOption:(NSDictionary<NSString *, id> *)option {
    NSString *current = option[@"value"];
    for (NSArray<NSString *> *pair in option[@"values"]) {
        if (pair.count > 0 && [pair[0] isEqualToString:current]) return pair.count > 1 ? pair[1] : pair[0];
    }
    return current ?: @"";
}

- (void)updateOptionRow:(UIButton *)row {
    if (row.tag < 0 || row.tag >= (NSInteger)self.coreOptions.count) return;
    UILabel *value = [row viewWithTag:900002];
    value.text = [NSString stringWithFormat:@"‹ %@ ›", [self labelForOption:self.coreOptions[(NSUInteger)row.tag]]];
}

- (void)layoutOptionsPage {
    if (_optionsView == nil) return;
    CGRect bounds = self.view.bounds;
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGFloat w = MIN(bounds.size.width - safe.left - safe.right - 24, 560);
    CGFloat h = bounds.size.height - safe.top - safe.bottom - 24;
    _optionsView.frame = CGRectMake(floor((bounds.size.width - w) * 0.5), safe.top + 12, w, h);
    OSLRLayoutPanelBackground(_optionsView);
    UIView *back = [_optionsView viewWithTag:900077];
    back.frame = CGRectMake(12, 12, 36, 36);
    _optionsTitle.frame = CGRectMake(54, 12, w - 66, 24);
    _optionsHint.frame = CGRectMake(54, 36, w - 66, 30);
    _optionsScroll.frame = CGRectMake(12, 72, w - 24, h - 84);
    CGFloat rowWidth = w - 24;
    CGFloat y = 0;
    NSUInteger headerIndex = 0;
    for (UIButton *row in _optionRows) {
        while (headerIndex < _optionHeaders.count && _optionHeaders[headerIndex].tag == row.tag) {
            _optionHeaders[headerIndex].frame = CGRectMake(6, y + 8, rowWidth - 12, 16);
            y += 28;
            headerIndex++;
        }
        row.frame = CGRectMake(0, y, rowWidth, 46);
        UIView *title = [row viewWithTag:900001];
        UIView *value = [row viewWithTag:900002];
        CGFloat valueWidth = MIN(rowWidth * 0.42, 220);
        title.frame = CGRectMake(14, 0, rowWidth - valueWidth - 34, 46);
        value.frame = CGRectMake(rowWidth - valueWidth - 14, 0, valueWidth, 46);
        y += 52;
    }
    _optionsScroll.contentSize = CGSizeMake(rowWidth, y);
}

- (void)refreshOptionsPage {
    for (UIButton *row in _optionRows) {
        OSLRStyleRow(row, row.tag == _optionIndex && _controller != nil);
    }
    if (_optionIndex >= 0 && _optionIndex < (NSInteger)_optionRows.count) {
        CGRect frame = CGRectInset(_optionRows[(NSUInteger)_optionIndex].frame, 0, -34);
        [_optionsScroll scrollRectToVisible:frame animated:YES];
    }
}

- (void)openOptionsPage {
    if (self.coreOptions.count == 0) return;
    _optionsVisible = YES;
    _optionIndex = 0;
    _menuView.hidden = YES;
    _optionsView.hidden = NO;
    [self.view bringSubviewToFront:_optionsView];
    [self layoutOptionsPage];
    [self refreshOptionsPage];
}

- (void)closeOptionsPage {
    if (!_optionsVisible) return;
    _optionsVisible = NO;
    _optionsView.hidden = YES;
    _menuView.hidden = NO;
    [self.view bringSubviewToFront:_menuView];
    [self refreshMenu];
}

- (void)optionRowTapped:(UIButton *)sender {
    _optionIndex = sender.tag;
    [self stepOption:sender.tag by:1];
    [self refreshOptionsPage];
}

/// Siguiente (o anterior) valor de una opción: se apunta, se le pasa al núcleo y se guarda.
- (void)stepOption:(NSInteger)index by:(NSInteger)delta {
    if (index < 0 || index >= (NSInteger)self.coreOptions.count) return;
    NSMutableDictionary<NSString *, id> *option = self.coreOptions[(NSUInteger)index];
    NSArray<NSArray<NSString *> *> *values = option[@"values"];
    if (values.count < 2) return;
    NSInteger position = 0;
    for (NSUInteger i = 0; i < values.count; i++) {
        if ([values[i].firstObject isEqualToString:option[@"value"]]) { position = (NSInteger)i; break; }
    }
    NSInteger count = (NSInteger)values.count;
    position = ((position + delta) % count + count) % count;
    NSString *value = values[(NSUInteger)position].firstObject;
    NSString *key = option[@"key"];
    if (value == nil || key == nil) return;
    option[@"value"] = value;
    [self updateOptionRow:_optionRows[(NSUInteger)index]];
    os_unfair_lock_lock(&gPendingLock);
    if (gPendingOptions == nil) gPendingOptions = [NSMutableDictionary new];
    gPendingOptions[key] = value;
    os_unfair_lock_unlock(&gPendingLock);
    if (self.optionChanged) self.optionChanged(key, value);
}

/// Filas que se ven: «Cambiar de disco» solo si el juego tiene varios discos.
- (void)updateVisibleRows {
    BOOL discs = atomic_load(&gDiskCount) > 1;
    NSMutableArray<UIButton *> *visible = [NSMutableArray new];
    for (UIButton *row in _menuRows) {
        BOOL show = (row.tag != OSLRMenuActionDisc || discs) && (row.tag != OSLRMenuActionOptions || self.coreOptions.count > 0);
        row.hidden = !show;
        if (show) [visible addObject:row];
    }
    _visibleRows = visible;
}

- (CGRect)videoFrameInBounds:(CGRect)bounds safe:(UIEdgeInsets)safe portrait:(BOOL)portrait {
    CGFloat w = bounds.size.width;
    CGFloat h = bounds.size.height;
    double aspect = atomic_load(&gAspect);
    if (self.stretch && !portrait) {
        return CGRectMake(safe.left, 0, w - safe.left - safe.right, h);
    }
    if (portrait) {
        // Arriba, dejando sitio debajo para los controles táctiles (NDS, con sus dos pantallas, algo más).
        CGFloat share = ([self.layout isEqualToString:@"nds"] || [self.layout isEqualToString:@"3ds"]) ? 0.64 : 0.55;
        CGFloat maxHeight = MAX(120, h * share - safe.top);
        CGFloat width = w;
        CGFloat height = floor(width / aspect);
        if (height > maxHeight) {
            height = maxHeight;
            width = floor(height * aspect);
        }
        CGFloat top = safe.top + MAX(0, floor((h * 0.5 - safe.top - height) * 0.5));
        return CGRectMake(floor((w - width) * 0.5), top, width, height);
    }
    CGFloat height = h;
    CGFloat width = floor(height * aspect);
    if (width > w) {
        width = w;
        height = floor(width / aspect);
    }
    return CGRectMake(floor((w - width) * 0.5), floor((h - height) * 0.5), width, height);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *root = self.view;
    CGFloat w = root.bounds.size.width;
    CGFloat h = root.bounds.size.height;
    UIEdgeInsets safe = root.safeAreaInsets;
    BOOL portrait = h > w;
    if (!_onTV) {
        self.videoView.frame = [self videoFrameInBounds:root.bounds safe:safe portrait:portrait];
    }
    // Opción que va con la orientación (NDS: una pantalla encima de otra o al lado). En la tele, al lado.
    if (gOrientKey != nil) atomic_store(&gOrientWanted, (portrait && !_onTV) ? 1 : 0);
    _controlsView.frame = root.bounds;
    CGFloat bottom = safe.bottom + 14;
    UIView *dpad = [_controlsView viewWithTag:1001];
    UIView *face = [_controlsView viewWithTag:1002];
    UIView *stick = [_controlsView viewWithTag:1003];
    UIView *cButtons = [_controlsView viewWithTag:1004];
    UIView *left = [_controlsView viewWithTag:1005];
    UIView *right = [_controlsView viewWithTag:1006];
    UIView *center = [_controlsView viewWithTag:1007];
    CGFloat rowY = h - bottom - 112 - (portrait ? 40 : 0);
    CGFloat upperY = rowY - 124;
    BOOL twoRows = stick != nil || cButtons != nil;
    if (stick != nil) {
        // Stick abajo a la izquierda y la cruceta (si la hay) encima.
        stick.frame = CGRectMake(safe.left + 14, rowY - 4, 120, 120);
        dpad.frame = CGRectMake(safe.left + 18, upperY, 112, 112);
    } else {
        dpad.frame = CGRectMake(safe.left + 18, rowY, 112, 112);
    }
    face.frame = CGRectMake(w - safe.right - 130, rowY, 112, 112);
    cButtons.frame = CGRectMake(w - safe.right - 130, upperY, 112, 112);
    if (portrait) {
        CGFloat shoulderY = (twoRows ? upperY : rowY) - 58;
        left.frame = CGRectMake(safe.left + 12, shoulderY, 108, 40);
        right.frame = CGRectMake(w - safe.right - 120, shoulderY, 108, 40);
    } else {
        left.frame = CGRectMake(safe.left + 12, safe.top + 60, 108, 40);
        right.frame = CGRectMake(w - safe.right - 120, safe.top + 60, 108, 40);
    }
    center.frame = CGRectMake(floor((w - 168) * 0.5), h - bottom - 34, 168, 34);
    _menuButton.frame = CGRectMake(safe.left + 14, safe.top + 12, 40, 40);
    if (self.hud) {
        CGSize size = [self.hud fittingSize];
        self.hud.frame = CGRectMake(w - safe.right - 10 - size.width, safe.top + 12, size.width, size.height);
    }
    _tvLabel.frame = CGRectMake(0, h * 0.30, w, 24);
    CGFloat labelWidth = MIN(w * 0.7, 420);
    _statusLabel.frame = CGRectMake((w - labelWidth) * 0.5, safe.top + 14, labelWidth, 54);
    _menuView.frame = root.bounds;
    CGFloat rowWidth = MIN(w - 40, 340);
    CGFloat rowHeight = 48;
    CGFloat total = rowHeight * (CGFloat)_visibleRows.count + 12 * (CGFloat)(_visibleRows.count - 1);
    CGFloat y = (h - total) * 0.5;
    _jitLabel.frame = CGRectMake((w - rowWidth) * 0.5, y - 58, rowWidth, 44);
    for (UIButton *row in _visibleRows) {
        row.frame = CGRectMake((w - rowWidth) * 0.5, y, rowWidth, rowHeight);
        y += rowHeight + 12;
    }
    if (_optionsVisible) [self layoutOptionsPage];
    if (_onTV) [self layoutTV];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    __weak OSLRGameViewController *weakSelf = self;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[GCControllerDidConnectNotification, GCControllerDidDisconnectNotification]) {
        [_observers addObject:[center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            [weakSelf bindController];
            [weakSelf updateControlsVisibility];
        }]];
    }
    [_observers addObject:[center addObserverForName:OSExternalDisplayDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        [weakSelf updateExternalDisplay];
    }]];
    [_observers addObject:[center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        atomic_store(&gBackground, true);
    }]];
    [_observers addObject:[center addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        atomic_store(&gBackground, false);
    }]];
    // Muy caliente: iOS baja la potencia y el juego puede ir lento o cerrarse; se avisa.
    [_observers addObject:[center addObserverForName:NSProcessInfoThermalStateDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        NSProcessInfoThermalState state = NSProcessInfo.processInfo.thermalState;
        if (state >= NSProcessInfoThermalStateSerious) {
            [weakSelf showStatus:[weakSelf t:@"El iPhone está muy caliente: el juego puede ir más lento o cerrarse" en:@"The iPhone is very hot: the game may slow down or close"]];
        }
    }]];
    [_observers addObject:[center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        OSLRGameViewController *strongSelf = weakSelf;
        if (strongSelf && !strongSelf.closing && !strongSelf->_menuVisible) [strongSelf openMenu];
    }]];
    [self bindController];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_displayLink == nil) {
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
        _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(30, 60, 60);
        [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    UIApplication.sharedApplication.idleTimerDisabled = YES;
    [self updateExternalDisplay];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_displayLink invalidate];
    _displayLink = nil;
    UIApplication.sharedApplication.idleTimerDisabled = NO;
}

- (void)dealloc {
    for (id token in _observers) [NSNotificationCenter.defaultCenter removeObserver:token];
    [self wireController:_controller enabled:NO];
}

// MARK: Mando físico

- (void)bindController {
    GCController *preferred = GCController.current.extendedGamepad ? GCController.current : nil;
    if (preferred == nil) {
        for (GCController *controller in GCController.controllers) {
            if (controller.extendedGamepad != nil) { preferred = controller; break; }
        }
    }
    if (preferred == _controller) return;
    [self wireController:_controller enabled:NO];
    _controller = preferred;
    [self wireController:_controller enabled:YES];
}

- (void)wireController:(GCController *)controller enabled:(BOOL)enabled {
    GCExtendedGamepad *pad = controller.extendedGamepad;
    if (pad == nil) return;
    if (!enabled) {
        pad.valueChangedHandler = nil;
        atomic_store(&gPadBits, 0);
        for (int index = 0; index < 4; index++) atomic_store(&gAxis[index], 0);
        return;
    }
    if (pad.buttonHome != nil) pad.buttonHome.preferredSystemGestureState = GCSystemGestureStateDisabled;
    __weak OSLRGameViewController *weakSelf = self;
    pad.valueChangedHandler = ^(GCExtendedGamepad *gamepad, GCControllerElement *element) {
        [weakSelf readGamepad:gamepad];
    };
    [self readGamepad:pad];
}

- (void)readGamepad:(GCExtendedGamepad *)pad {
    if (pad == nil) return;
    uint32_t physical = 0;
    #define OSLR_SET(condition, button) if (condition) physical |= (1u << (button))
    OSLR_SET(pad.buttonA.isPressed, RETRO_DEVICE_ID_JOYPAD_B);
    OSLR_SET(pad.buttonB.isPressed, RETRO_DEVICE_ID_JOYPAD_A);
    OSLR_SET(pad.buttonX.isPressed, RETRO_DEVICE_ID_JOYPAD_Y);
    OSLR_SET(pad.buttonY.isPressed, RETRO_DEVICE_ID_JOYPAD_X);
    OSLR_SET(pad.leftShoulder.isPressed, RETRO_DEVICE_ID_JOYPAD_L);
    OSLR_SET(pad.rightShoulder.isPressed, RETRO_DEVICE_ID_JOYPAD_R);
    OSLR_SET(pad.leftTrigger.isPressed, RETRO_DEVICE_ID_JOYPAD_L2);
    OSLR_SET(pad.rightTrigger.isPressed, RETRO_DEVICE_ID_JOYPAD_R2);
    OSLR_SET(pad.leftThumbstickButton.isPressed, RETRO_DEVICE_ID_JOYPAD_L3);
    OSLR_SET(pad.rightThumbstickButton.isPressed, RETRO_DEVICE_ID_JOYPAD_R3);
    OSLR_SET(pad.buttonMenu.isPressed, RETRO_DEVICE_ID_JOYPAD_START);
    OSLR_SET(pad.buttonOptions.isPressed, RETRO_DEVICE_ID_JOYPAD_SELECT);
    // La cruceta y el stick izquierdo mueven igual (los juegos 2D no usan el stick).
    float x = pad.dpad.xAxis.value, y = pad.dpad.yAxis.value;
    float lx = pad.leftThumbstick.xAxis.value, ly = pad.leftThumbstick.yAxis.value;
    OSLR_SET(y > 0.5f || ly > 0.6f, RETRO_DEVICE_ID_JOYPAD_UP);
    OSLR_SET(y < -0.5f || ly < -0.6f, RETRO_DEVICE_ID_JOYPAD_DOWN);
    OSLR_SET(x < -0.5f || lx < -0.6f, RETRO_DEVICE_ID_JOYPAD_LEFT);
    OSLR_SET(x > 0.5f || lx > 0.6f, RETRO_DEVICE_ID_JOYPAD_RIGHT);
    #undef OSLR_SET
    _physicalBits = physical;
    // Mapa de botones del juego (solo los botones, no la cruceta).
    uint32_t output = physical;
    if (self.buttonMap.count > 0) {
        uint32_t directions = (1u << RETRO_DEVICE_ID_JOYPAD_UP) | (1u << RETRO_DEVICE_ID_JOYPAD_DOWN) |
                              (1u << RETRO_DEVICE_ID_JOYPAD_LEFT) | (1u << RETRO_DEVICE_ID_JOYPAD_RIGHT);
        output = physical & directions;
        for (unsigned button = 0; button < 16; button++) {
            if (!(physical & (1u << button)) || (directions & (1u << button))) continue;
            NSNumber *target = self.buttonMap[@(button)];
            output |= 1u << (target ? target.unsignedIntValue : button);
        }
    }
    atomic_store(&gPadBits, output);
    atomic_store(&gAxis[0], (int32_t)(lx * 32767.0f));
    atomic_store(&gAxis[1], (int32_t)(-ly * 32767.0f));
    atomic_store(&gAxis[2], (int32_t)(pad.rightThumbstick.xAxis.value * 32767.0f));
    atomic_store(&gAxis[3], (int32_t)(-pad.rightThumbstick.yAxis.value * 32767.0f));
}

// MARK: Ritmo de pantalla: imagen, menú y HUD

- (void)tick {
    uint64_t serial = _lastSerial;
    CGImageRef image = OSLRCopyFrameImage(&serial);
    _lastSerial = serial;
    if (image != NULL) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.videoView.layer.contents = (__bridge id)image;
        [CATransaction commit];
        CGImageRelease(image);
    }
    if (atomic_exchange(&gGeometryChanged, false)) [self.view setNeedsLayout];
    [self pollMenuInput];
    if (self.hud) {
        double now = OSLRNow();
        if (_hudTime == 0) {
            _hudTime = now;
            _hudFrames = atomic_load(&gFrameCount);
        } else if (now - _hudTime >= 0.5) {
            uint64_t frames = atomic_load(&gFrameCount);
            double fps = (double)(frames - _hudFrames) / (now - _hudTime);
            _hudTime = now;
            _hudFrames = frames;
            [self.hud refreshWithFPS:fps frameTime:fps > 0 ? 1000.0 / fps : 0 fifo:0];
            [self.view setNeedsLayout];
        }
    }
}

- (void)pollMenuInput {
    GCExtendedGamepad *pad = _controller.extendedGamepad;
    if (pad == nil) return;
    BOOL home = pad.buttonHome != nil && pad.buttonHome.isPressed;
    BOOL combo = pad.buttonMenu.isPressed && pad.buttonOptions != nil && pad.buttonOptions.isPressed;
    float y = pad.dpad.yAxis.value;
    if (fabsf(y) < 0.5f) y = pad.leftThumbstick.yAxis.value;
    BOOL up = y > 0.5f, down = y < -0.5f;
    float x = pad.dpad.xAxis.value;
    if (fabsf(x) < 0.5f) x = pad.leftThumbstick.xAxis.value;
    BOOL left = x < -0.5f, right = x > 0.5f;
    BOOL a = pad.buttonA.isPressed, b = pad.buttonB.isPressed;
    if (_menuVisible && _optionsVisible && !self.closing) {
        NSInteger count = (NSInteger)_optionRows.count;
        if (count > 0) {
            if (up && !_prevUp) { _optionIndex = (_optionIndex + count - 1) % count; [self refreshOptionsPage]; }
            if (down && !_prevDown) { _optionIndex = (_optionIndex + 1) % count; [self refreshOptionsPage]; }
            if (left && !_prevLeft) [self stepOption:_optionIndex by:-1];
            if ((right && !_prevRight) || (a && !_prevA)) [self stepOption:_optionIndex by:1];
        }
        if (b && !_prevB) [self closeOptionsPage];
        if (home && !_prevHome) { [self closeOptionsPage]; [self closeMenu]; }
        _prevHome = home; _prevCombo = combo; _prevUp = up; _prevDown = down; _prevA = a; _prevB = b;
        _prevLeft = left; _prevRight = right;
        return;
    }
    if (!_menuVisible) {
        if ((home && !_prevHome) || (combo && !_prevCombo)) [self openMenu];
    } else if (!self.closing) {
        NSInteger count = (NSInteger)_visibleRows.count;
        if (count > 0) {
            if (up && !_prevUp) { _menuIndex = (_menuIndex + count - 1) % count; [self refreshMenu]; }
            if (down && !_prevDown) { _menuIndex = (_menuIndex + 1) % count; [self refreshMenu]; }
            if (a && !_prevA && _menuIndex < count) [self activateRow:_visibleRows[_menuIndex].tag];
        }
        if ((b && !_prevB) || (home && !_prevHome)) [self closeMenu];
    }
    _prevHome = home; _prevCombo = combo; _prevUp = up; _prevDown = down; _prevA = a; _prevB = b;
    _prevLeft = left; _prevRight = right;
}

// MARK: Menú

- (void)refreshMenu {
    UIButton *current = _menuIndex < (NSInteger)_visibleRows.count ? _visibleRows[_menuIndex] : nil;
    for (UIButton *row in _menuRows) {
        OSLRStyleRow(row, row == current && _controller != nil);
    }
}

- (void)openMenu {
    if (_menuVisible || self.closing) return;
    // El núcleo pidió memoria de JIT y nadie se la preparó: esta partida va sin JIT de verdad.
    if (self.jitOn && gJITUnanswered) {
        self.jitOn = NO;
        self.jitText = [self t:@"Sin JIT: el depurador no preparó la memoria del núcleo" en:@"No JIT: the debugger did not prepare the core's memory"];
        [self updateJITLabel];
    } else if (self.jitOn && gJITPoolCore && !atomic_load(&gJITPoolGiven)) {
        // Núcleo con JIT permanente al que no se le pudo dar: va en modo intérprete.
        self.jitOn = NO;
        self.jitText = [NSString stringWithFormat:@"%@ (%@)", [self t:@"Sin JIT: no se pudo preparar el JIT permanente" en:@"No JIT: the permanent JIT could not be prepared"], gJITPoolStatus ?: @"?"];
        [self updateJITLabel];
    }
    _menuVisible = YES;
    _menuIndex = 0;
    [self updateVisibleRows];
    [self.view setNeedsLayout];
    [self refreshMenu];
    _menuView.hidden = NO;
    [self.view bringSubviewToFront:_menuView];
    atomic_store(&gTouchBits, 0);
    if (self.menuChanged) self.menuChanged(YES);
}

- (void)closeMenu {
    if (!_menuVisible) return;
    if (_optionsVisible) {
        _optionsVisible = NO;
        _optionsView.hidden = YES;
    }
    _menuVisible = NO;
    _menuView.hidden = YES;
    if (self.menuChanged) self.menuChanged(NO);
}

- (void)menuRowTapped:(UIButton *)sender {
    [self activateRow:sender.tag];
}

- (void)activateRow:(NSInteger)action {
    if (action == OSLRMenuActionOptions) {
        [self openOptionsPage];
        return;
    }
    if (action != OSLRMenuActionQuit) [self closeMenu];
    if (self.menuAction) self.menuAction(action);
}

- (void)showStatus:(NSString *)message {
    _statusLabel.text = message;
    [self.view bringSubviewToFront:_statusLabel];
    NSUInteger token = ++_statusToken;
    [UIView animateWithDuration:0.2 animations:^{ self->_statusLabel.alpha = 1; }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token != self->_statusToken) return;
        [UIView animateWithDuration:0.3 animations:^{ self->_statusLabel.alpha = 0; }];
    });
}

// MARK: Tele

- (void)layoutTV {
    if (_tvHost == nil) return;
    CGRect bounds = _tvHost.bounds;
    self.videoView.frame = [self videoFrameInBounds:bounds safe:UIEdgeInsetsZero portrait:NO];
}

- (void)updateExternalDisplay {
    BOOL wantTV = OSExternalDisplay.enabled && OSExternalDisplay.shared.connected;
    if (wantTV && !_onTV) {
        if (_tvHost == nil) {
            _tvHost = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1920, 1080)];
            _tvHost.backgroundColor = UIColor.blackColor;
            _tvHost.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        }
        [_tvHost addSubview:self.videoView];
        if ([OSExternalDisplay.shared hostView:_tvHost]) {
            _onTV = YES;
            _tvLabel.hidden = NO;
            [self layoutTV];
            dispatch_async(dispatch_get_main_queue(), ^{ [self layoutTV]; });
        } else {
            [self returnVideoToPhone];
        }
    } else if (!wantTV && _onTV) {
        [self releaseExternalDisplay];
    }
    [self updateControlsVisibility];
}

- (void)returnVideoToPhone {
    [self.view insertSubview:self.videoView atIndex:0];
    [self.view setNeedsLayout];
}

- (void)releaseExternalDisplay {
    if (!_onTV) return;
    _onTV = NO;
    _tvLabel.hidden = YES;
    [self returnVideoToPhone];
    [OSExternalDisplay.shared releaseView:_tvHost];
}

@end

// MARK: - Sonido (AVAudioEngine)

@interface OSLRAudio : NSObject
- (BOOL)startWithSampleRate:(double)rate;
- (void)stop;
@end

@implementation OSLRAudio {
    AVAudioEngine *_engine;
    AVAudioSourceNode *_source;
    NSMutableArray<id> *_observers;
}

- (BOOL)startWithSampleRate:(double)rate {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    [session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];
    [session setPreferredIOBufferDuration:0.02 error:nil];
    atomic_store(&gAudioPrimed, false);
    [session setActive:YES error:nil];
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:rate channels:2];
    if (format == nil) return NO;
    _engine = [AVAudioEngine new];
    _source = [[AVAudioSourceNode alloc] initWithFormat:format renderBlock:^OSStatus(BOOL *isSilence, const AudioTimeStamp *timestamp, AVAudioFrameCount frameCount, AudioBufferList *outputData) {
        float *left = outputData->mNumberBuffers > 0 ? (float *)outputData->mBuffers[0].mData : NULL;
        float *right = outputData->mNumberBuffers > 1 ? (float *)outputData->mBuffers[1].mData : left;
        if (left == NULL) return noErr;
        atomic_store_explicit(&gLastAudioPull, OSLRNow(), memory_order_relaxed);
        size_t read = atomic_load_explicit(&gAudioRead, memory_order_relaxed);
        size_t write = atomic_load_explicit(&gAudioWrite, memory_order_acquire);
        size_t available = write - read;
        size_t count = MIN((size_t)frameCount, available);
        size_t margin = (size_t)(gSampleRate * 0.06);
        if (!atomic_load_explicit(&gAudioPrimed, memory_order_relaxed)) {
            if (available >= margin + frameCount) {
                atomic_store_explicit(&gAudioPrimed, true, memory_order_relaxed);
            } else {
                count = 0;
            }
        } else if (available < frameCount) {
            atomic_store_explicit(&gAudioPrimed, false, memory_order_relaxed);
        }
        float volume = atomic_load(&gVolume) / 32768.0f;
        for (size_t index = 0; index < count; index++) {
            size_t slot = (read + index) % gAudioCapacity;
            left[index] = (float)gAudioRing[slot * 2] * volume;
            if (right != left) right[index] = (float)gAudioRing[slot * 2 + 1] * volume;
        }
        for (size_t index = count; index < frameCount; index++) {
            left[index] = 0;
            if (right != left) right[index] = 0;
        }
        atomic_store_explicit(&gAudioRead, read + count, memory_order_release);
        return noErr;
    }];
    [_engine attachNode:_source];
    [_engine connect:_source to:_engine.mainMixerNode format:format];
    NSError *error = nil;
    if (![_engine startAndReturnError:&error]) {
        printf("[OmniStation] libretro: no se pudo arrancar el sonido: %s\n", error.localizedDescription.UTF8String);
        return NO;
    }
    // Si iOS para el sonido (cambio de salida, una llamada…), se vuelve a arrancar: si no, el juego
    // seguiría mudo y esperando a que suene.
    _observers = [NSMutableArray new];
    __weak AVAudioEngine *weakEngine = _engine;
    void (^restart)(NSNotification *) = ^(NSNotification *note) {
        AVAudioEngine *engine = weakEngine;
        if (engine == nil || engine.isRunning) return;
        atomic_store(&gAudioPrimed, false);
        [AVAudioSession.sharedInstance setActive:YES error:nil];
        [engine prepare];
        [engine startAndReturnError:nil];
    };
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [_observers addObject:[center addObserverForName:AVAudioEngineConfigurationChangeNotification object:_engine
                                               queue:NSOperationQueue.mainQueue usingBlock:restart]];
    [_observers addObject:[center addObserverForName:AVAudioSessionInterruptionNotification object:nil
                                               queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        NSNumber *type = note.userInfo[AVAudioSessionInterruptionTypeKey];
        if (type.unsignedIntegerValue == AVAudioSessionInterruptionTypeEnded) restart(note);
    }]];
    return YES;
}

- (void)stop {
    for (id observer in _observers) [NSNotificationCenter.defaultCenter removeObserver:observer];
    _observers = nil;
    [_engine stop];
    if (_source) [_engine detachNode:_source];
    _source = nil;
    _engine = nil;
}

@end

// MARK: - Motor

@interface OSLibretroEngine ()
@property (nonatomic, assign) BOOL busy;
@property (atomic, assign) NSUInteger lastSessionPeakMB;
@property (atomic, copy, nullable) NSArray<NSDictionary<NSString *, id> *> *lastSessionOptions;
@property (nonatomic, strong, nullable) OSLRGameViewController *gameController;
@property (nonatomic, copy, nullable) void (^endedHandler)(void);
@end

@implementation OSLibretroEngine {
    NSMutableDictionary<NSString *, NSValue *> *_handles;
    NSThread *_thread;
    OSLRAudio *_audio;
    NSData *_gameData;
    NSString *_savePath;
    NSString *_statePath;
    NSString *_language;
}

+ (OSLibretroEngine *)shared {
    static OSLibretroEngine *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [OSLibretroEngine new]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _handles = [NSMutableDictionary new];
        atomic_store(&gPendingAction, -1);
    }
    return self;
}

+ (NSString *)binaryPathForFramework:(NSString *)framework {
    NSString *frameworks = NSBundle.mainBundle.privateFrameworksPath ?: [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks"];
    NSString *folder = [frameworks stringByAppendingPathComponent:framework];
    NSString *name = framework.stringByDeletingPathExtension;
    NSString *binary = [folder stringByAppendingPathComponent:name];
    // Si el Info.plist dice otro ejecutable, ese.
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[folder stringByAppendingPathComponent:@"Info.plist"]];
    NSString *executable = info[@"CFBundleExecutable"];
    if ([executable isKindOfClass:NSString.class] && executable.length > 0) {
        binary = [folder stringByAppendingPathComponent:executable];
    }
    return binary;
}

+ (BOOL)jitActive {
    if (!OSLRIsDebugged()) return NO;
    // En iOS 26 el JIT necesita el depurador enganchado (CS_DEBUGGED se queda aunque se suelte).
    return OSLRUsesJITScript() ? OSLRIsTraced() : YES;
}

+ (BOOL)persistentJITReady {
    os_unfair_lock_lock(&gJITPoolLock);
    BOOL ready = gJITPoolRX != NULL;
    os_unfair_lock_unlock(&gJITPoolLock);
    return ready;
}

+ (BOOL)preparePersistentJIT {
    return OSLRPrepareJITPool();
}

+ (NSString *)persistentJITStatus {
    if ([self persistentJITReady]) return @"ready";
    return gJITPoolStatus ?: @"";
}

+ (void)detachJITDebugger {
    if (!OSLRUsesJITScript() || !OSLRIsTraced()) return;
    OSLRInstallTrapGuard(YES);
    OSLRUniversalDetach();
}

- (NSArray<NSDictionary<NSString *, id> *> *)optionsForCore:(NSString *)framework language:(NSString *)language {
    if (self.busy || ![OSLibretroEngine coreAvailable:framework]) return nil;
    NSString *error = nil;
    if (![self loadCore:framework error:&error]) return nil;
    gLanguage = [language isEqualToString:@"en"] ? RETRO_LANGUAGE_ENGLISH : RETRO_LANGUAGE_SPANISH;
    gCaptured = [NSMutableArray new];
    gCapturedCategories = [NSMutableDictionary new];
    gCapturing = YES;
    // Solo retro_set_environment (libretro deja llamarla sin más). Nunca retro_init/retro_deinit
    // fuera de una partida: núcleos como el de Wii no se recuperan bien de eso y la partida
    // siguiente fallaba. Los que declaran sus opciones al prepararse se apuntan al jugar.
    gCore.setEnvironment(OSLREnvironment);
    gCapturing = NO;
    NSArray<NSDictionary<NSString *, id> *> *result = OSLRCapturedList();
    gCaptured = nil;
    gCapturedCategories = nil;
    return result;
}

+ (BOOL)coreAvailable:(NSString *)framework {
    if (framework.length == 0) return NO;
    return [NSFileManager.defaultManager fileExistsAtPath:[self binaryPathForFramework:framework]];
}

- (BOOL)loadCore:(NSString *)framework error:(NSString **)error {
    NSString *path = [OSLibretroEngine binaryPathForFramework:framework];
    void *handle = _handles[framework].pointerValue;
    if (handle == NULL) {
        dlerror();
        handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
        if (handle == NULL) {
            const char *detail = dlerror();
            if (error) *error = [NSString stringWithFormat:@"No se pudo cargar el núcleo: %s", detail ? detail : "?"];
            return NO;
        }
        _handles[framework] = [NSValue valueWithPointer:handle];
    }
    OSLRCore core;
    memset(&core, 0, sizeof(core));
    NSMutableArray<NSString *> *missing = [NSMutableArray new];
    #define OSLR_SYMBOL(field, name) do { \
        core.field = (__typeof__(core.field))dlsym(handle, name); \
        if (core.field == NULL) [missing addObject:[NSString stringWithUTF8String:name]]; \
    } while (0)
    OSLR_SYMBOL(init, "retro_init");
    OSLR_SYMBOL(deinit, "retro_deinit");
    OSLR_SYMBOL(apiVersion, "retro_api_version");
    OSLR_SYMBOL(getSystemInfo, "retro_get_system_info");
    OSLR_SYMBOL(getSystemAVInfo, "retro_get_system_av_info");
    OSLR_SYMBOL(setEnvironment, "retro_set_environment");
    OSLR_SYMBOL(setVideoRefresh, "retro_set_video_refresh");
    OSLR_SYMBOL(setAudioSample, "retro_set_audio_sample");
    OSLR_SYMBOL(setAudioSampleBatch, "retro_set_audio_sample_batch");
    OSLR_SYMBOL(setInputPoll, "retro_set_input_poll");
    OSLR_SYMBOL(setInputState, "retro_set_input_state");
    OSLR_SYMBOL(setControllerPortDevice, "retro_set_controller_port_device");
    OSLR_SYMBOL(reset, "retro_reset");
    OSLR_SYMBOL(run, "retro_run");
    OSLR_SYMBOL(serializeSize, "retro_serialize_size");
    OSLR_SYMBOL(serialize, "retro_serialize");
    OSLR_SYMBOL(unserialize, "retro_unserialize");
    OSLR_SYMBOL(loadGame, "retro_load_game");
    OSLR_SYMBOL(unloadGame, "retro_unload_game");
    OSLR_SYMBOL(getMemoryData, "retro_get_memory_data");
    OSLR_SYMBOL(getMemorySize, "retro_get_memory_size");
    #undef OSLR_SYMBOL
    if (missing.count > 0) {
        if (error) *error = [@"El núcleo no es libretro o está incompleto. Falta: " stringByAppendingString:[missing componentsJoinedByString:@", "]];
        return NO;
    }
    if (core.apiVersion() != RETRO_API_VERSION) {
        if (error) *error = @"Versión de libretro distinta.";
        return NO;
    }
    gCore = core;
    snprintf(gCorePath, sizeof(gCorePath), "%s", path.fileSystemRepresentation);
    return YES;
}

- (UIViewController *)topViewController {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) { keyWindow = window; break; }
        }
        if (keyWindow) break;
    }
    UIViewController *controller = keyWindow.rootViewController;
    while (controller.presentedViewController) controller = controller.presentedViewController;
    return controller;
}

// MARK: Partidas y estados (hilo de emulación)

- (void)loadSaveRAM {
    if (_savePath == nil || gCore.getMemoryData == NULL) return;
    void *memory = gCore.getMemoryData(RETRO_MEMORY_SAVE_RAM);
    size_t size = gCore.getMemorySize(RETRO_MEMORY_SAVE_RAM);
    if (memory == NULL || size == 0) return;
    NSData *data = [NSData dataWithContentsOfFile:_savePath];
    if (data.length == 0) return;
    memcpy(memory, data.bytes, MIN(size, data.length));
}

/// Guarda la partida si cambió desde la última vez (`last` es la copia de entonces).
- (void)writeSaveRAMIfChanged:(NSMutableData *)last {
    if (_savePath == nil) return;
    void *memory = gCore.getMemoryData(RETRO_MEMORY_SAVE_RAM);
    size_t size = gCore.getMemorySize(RETRO_MEMORY_SAVE_RAM);
    if (memory == NULL || size == 0) return;
    if (last.length == size && memcmp(last.mutableBytes, memory, size) == 0) return;
    NSData *data = [NSData dataWithBytes:memory length:size];
    if ([data writeToFile:_savePath atomically:YES]) {
        [last setData:data];
    }
}

- (BOOL)saveState {
    size_t size = gCore.serializeSize();
    if (size == 0 || _statePath == nil) return NO;
    NSMutableData *data = [NSMutableData dataWithLength:size];
    if (!gCore.serialize(data.mutableBytes, size)) return NO;
    return [data writeToFile:_statePath atomically:YES];
}

- (BOOL)loadState {
    NSData *data = _statePath ? [NSData dataWithContentsOfFile:_statePath] : nil;
    if (data.length == 0) return NO;
    return gCore.unserialize(data.bytes, data.length);
}

- (void)showStatus:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{ [self.gameController showStatus:message]; });
}

/// Siguiente disco (juegos de varios discos): se abre la bandeja, se cambia y se cierra.
- (void)changeDisc {
    if (!gHasDisk || gDisk.get_num_images == NULL || gDisk.set_image_index == NULL || gDisk.get_image_index == NULL) return;
    unsigned count = gDisk.get_num_images();
    if (count < 2) return;
    unsigned next = (gDisk.get_image_index() + 1) % count;
    if (gDisk.set_eject_state) gDisk.set_eject_state(true);
    BOOL ok = gDisk.set_image_index(next);
    if (gDisk.set_eject_state) gDisk.set_eject_state(false);
    atomic_store(&gDiskCount, count);
    NSString *spanish = [NSString stringWithFormat:@"Disco %u de %u", next + 1, count];
    NSString *english = [NSString stringWithFormat:@"Disc %u of %u", next + 1, count];
    [self showStatus:ok ? OSLRText(_language, spanish, english) : OSLRText(_language, @"No se pudo cambiar de disco", @"Could not change disc")];
}

// MARK: Bucle de emulación

- (void)emulationLoopWithFramework:(NSString *)framework
                          gamePath:(NSString *)gamePath
                        completion:(void (^)(BOOL, NSString *))completion {
    __block NSString *failure = nil;
    BOOL loaded = NO;
    @autoreleasepool {
        // Se apuntan las opciones que declare (para sus ajustes) mientras se prepara.
        gCaptured = [NSMutableArray new];
        gCapturedCategories = [NSMutableDictionary new];
        gRecording = YES;
        gCore.setEnvironment(OSLREnvironment);
        gCore.setVideoRefresh(OSLRVideoRefresh);
        gCore.setAudioSample(OSLRAudioSample);
        gCore.setAudioSampleBatch(OSLRAudioSampleBatch);
        gCore.setInputPoll(OSLRInputPoll);
        gCore.setInputState(OSLRInputState);
        gCore.init();
        struct retro_system_info coreInfo;
        memset(&coreInfo, 0, sizeof(coreInfo));
        gCore.getSystemInfo(&coreInfo);
        struct retro_game_info game;
        memset(&game, 0, sizeof(game));
        snprintf(gGamePath, sizeof(gGamePath), "%s", gamePath.fileSystemRepresentation);
        game.path = gGamePath;
        if (!coreInfo.need_fullpath) {
            _gameData = [NSData dataWithContentsOfFile:gamePath options:NSDataReadingMappedIfSafe error:nil];
            if (_gameData == nil) failure = OSLRText(_language, @"No se puede leer el archivo del juego.", @"The game file cannot be read.");
            game.data = _gameData.bytes;
            game.size = _gameData.length;
        }
        if (failure == nil) {
            loaded = gCore.loadGame(&game);
            if (!loaded) {
                NSString *said = nil;
                @synchronized ([OSLibretroEngine class]) { said = gLastCoreMessage; }
                failure = OSLRText(_language, @"El núcleo no pudo abrir este juego.", @"The core could not open this game.");
                if (said.length > 0) failure = [NSString stringWithFormat:@"%@ (%@)", failure, said];
            }
        }
        gRecording = NO;
        OSLRTrace(loaded ? @"abrir: juego cargado" : [NSString stringWithFormat:@"abrir: el núcleo no pudo cargar el juego%@", failure.length ? [@": " stringByAppendingString:failure] : @""], NO);
        self.lastSessionOptions = OSLRCapturedList();
        gCaptured = nil;
        gCapturedCategories = nil;
        struct retro_system_av_info av;
        memset(&av, 0, sizeof(av));
        if (loaded) {
            gCore.getSystemAVInfo(&av);
            OSLRUpdateGeometry(&av.geometry);
            // Imagen por GPU: el contexto se crea ahora y el núcleo prepara lo suyo (context_reset).
            if (gHWRequested && gHWCallback.context_type == RETRO_HW_CONTEXT_VULKAN) {
                if (OSLRCreateVulkan()) {
                    if (gHWCallback.context_reset) gHWCallback.context_reset();
                } else {
                    failure = OSLRText(_language, @"No se pudo preparar la imagen por GPU (Vulkan).", @"Could not set up GPU rendering (Vulkan).");
                    gCore.unloadGame();
                    OSLRDestroyVulkan();
                    loaded = NO;
                }
            } else if (gHWRequested) {
                unsigned width = MAX(av.geometry.max_width, av.geometry.base_width);
                unsigned height = MAX(av.geometry.max_height, av.geometry.base_height);
                if (OSLRCreateGL(width > 0 ? width : 640, height > 0 ? height : 480)) {
                    if (gHWCallback.context_reset) gHWCallback.context_reset();
                } else {
                    failure = OSLRText(_language, @"No se pudo preparar la imagen por GPU (OpenGL ES).", @"Could not set up GPU rendering (OpenGL ES).");
                    gCore.unloadGame();
                    OSLRDestroyGL();
                    loaded = NO;
                }
            }
            if (loaded && gHasDisk && gDisk.get_num_images) atomic_store(&gDiskCount, gDisk.get_num_images());
        }
        if (loaded) {
            gFPS = av.timing.fps > 1 ? av.timing.fps : 60.0;
            gSampleRate = av.timing.sample_rate > 1000 ? av.timing.sample_rate : 44100.0;
            gCore.setControllerPortDevice(0, RETRO_DEVICE_JOYPAD);
            [self loadSaveRAM];
            // Anillo de sonido de medio segundo.
            gAudioCapacity = (size_t)(gSampleRate * 0.5);
            gAudioRing = calloc(gAudioCapacity * 2, sizeof(int16_t));
            atomic_store(&gAudioWrite, 0);
            atomic_store(&gAudioRead, 0);
        }
    }
    dispatch_sync(dispatch_get_main_queue(), ^{
        if (loaded) {
            self->_audio = [OSLRAudio new];
            [self->_audio startWithSampleRate:gSampleRate];
            // Núcleo que declara sus opciones al prepararse: ahora ya se conocen y el menú de la
            // partida puede enseñarlas desde esta misma partida.
            if (self.gameController.coreOptions.count == 0 && self.menuOptionsProvider) {
                NSArray<NSDictionary<NSString *, id> *> *late = self.menuOptionsProvider();
                if (late.count > 0) [self.gameController reloadCoreOptions:OSLRMenuOptions(late)];
            }
        } else {
            // Si no arranca, solo se avisa por `completion` (no también por `ended`).
            self.endedHandler = nil;
        }
        completion(loaded, failure ?: @"");
    });
    if (!loaded) {
        gCore.deinit();
        OSLRDestroyGL();
        OSLRDestroyVulkan();
        @synchronized (gJITSessionBlocks) {
            for (NSValue *block in gJITSessionBlocks) OSLRJITPoolFree(block.pointerValue);
            [gJITSessionBlocks removeAllObjects];
        }
        [self finishSession];
        return;
    }

    NSMutableData *lastSave = [NSMutableData new];
    {
        void *memory = gCore.getMemoryData(RETRO_MEMORY_SAVE_RAM);
        size_t size = gCore.getMemorySize(RETRO_MEMORY_SAVE_RAM);
        if (memory && size) [lastSave setData:[NSData dataWithBytes:memory length:size]];
    }
    double frameTime = 1.0 / gFPS;
    double next = OSLRNow();
    double lastAutosave = next;
    double lastMemoryCheck = 0;
    // El depurador se suelta solo a los pocos segundos de jugar (ver abajo).
    double sessionStart = next;
    BOOL debuggerSettled = NO;
    while (atomic_load(&gRunning) && !atomic_load(&gShutdownRequested)) {
        @autoreleasepool {
            int action = atomic_exchange(&gPendingAction, -1);
            if (action == OSLRMenuActionSaveState) {
                BOOL ok = [self saveState];
                [self showStatus:ok ? OSLRText(_language, @"Estado guardado", @"State saved") : OSLRText(_language, @"No se pudo guardar el estado", @"Could not save the state")];
            } else if (action == OSLRMenuActionLoadState) {
                BOOL ok = [self loadState];
                [self showStatus:ok ? OSLRText(_language, @"Estado cargado", @"State loaded") : OSLRText(_language, @"No hay estado guardado", @"No saved state")];
            } else if (action == OSLRMenuActionReset) {
                gCore.reset();
            } else if (action == OSLRMenuActionDisc) {
                [self changeDisc];
            }
            if (atomic_load(&gPaused) || atomic_load(&gBackground)) {
                [NSThread sleepForTimeInterval:0.02];
                next = OSLRNow();
                continue;
            }
            // Opciones cambiadas en el menú de la partida: se le pasan al núcleo.
            os_unfair_lock_lock(&gPendingLock);
            NSDictionary<NSString *, NSString *> *pending = gPendingOptions.count ? [gPendingOptions copy] : nil;
            [gPendingOptions removeAllObjects];
            os_unfair_lock_unlock(&gPendingLock);
            if (pending) {
                NSMutableDictionary<NSString *, NSString *> *options = [gUserOptions mutableCopy] ?: [NSMutableDictionary new];
                [options addEntriesFromDictionary:pending];
                gUserOptions = options;
                atomic_store(&gVariablesChanged, true);
            }
            // La orientación cambió: la opción que va con ella (NDS) se le pasa al núcleo.
            int orientation = atomic_load(&gOrientWanted);
            if (gOrientKey != nil && orientation >= 0 && orientation != gOrientApplied) {
                gOrientApplied = orientation;
                NSMutableDictionary<NSString *, NSString *> *options = [gUserOptions mutableCopy] ?: [NSMutableDictionary new];
                NSString *value = orientation == 1 ? gOrientPortrait : gOrientLandscape;
                if (value) options[gOrientKey] = value;
                gUserOptions = options;
                atomic_store(&gVariablesChanged, true);
            }
            frameTime = 1.0 / gFPS;
            if (gHasFrameTimeCallback) gFrameTimeCallback.callback(gFrameTimeCallback.reference);
            gCore.run();
            // Ritmo del juego; si el sonido se llena o se vacía, se corrige un poco.
            double fill = OSLRAudioFill();
            double adjust = fill > 0.6 ? 1.02 : (fill < 0.2 ? 0.98 : 1.0);
            next += frameTime * adjust;
            double now = OSLRNow();
            if (next > now) {
                [NSThread sleepForTimeInterval:next - now];
            } else if (now - next > frameTime * 3) {
                // Atrasado (un fotograma lento, el JIT preparándose o vuelta de una pausa): se sigue
                // desde ahora. Recuperar de golpe muchos fotogramas se nota como cámara rápida y
                // llena el sonido hasta que se pierde (microcortes).
                next = now;
            }
            // El sonido manda: si el núcleo va más deprisa que lo que suena (algunos, como el de
            // 3DS, entregan el sonido a ráfagas), se espera a que haya sitio en vez de tirarlo.
            BOOL audioAlive = OSLRNow() - atomic_load(&gLastAudioPull) < 0.15;
            for (int wait = 0; audioAlive && wait < 25 && OSLRAudioFill() > 0.75 && atomic_load(&gRunning); wait++) {
                [NSThread sleepForTimeInterval:0.002];
                next = OSLRNow();
            }
            if (now - lastAutosave > 10) {
                lastAutosave = now;
                [self writeSaveRAMIfChanged:lastSave];
            }
            // A los 4 s de partida, el núcleo ya preparó su memoria de JIT. Si el depurador sigue
            // enganchado, se suelta: con él puesto, cada aviso del sistema (los fallos de página que
            // usan Dolphin o melonDS para ir rápido) pasa por StikDebug y la VPN, lo que calienta,
            // ralentiza, hace lento el cierre y corta el JIT si cambia la red. Sin él, el JIT ya
            // preparado sigue valiendo.
            if (!debuggerSettled && now - sessionStart > 4.0) {
                debuggerSettled = YES;
                if (gJITCapable && OSLRUsesJITScript() && OSLRIsTraced()) {
                    OSLRTrace(@"JIT: se suelta el depurador (la memoria de JIT ya está preparada)", NO);
                    OSLRInstallTrapGuard(YES);
                    OSLRUniversalDetach();
                    void (^released)(void) = self.debuggerReleasedHandler;
                    if (released) dispatch_async(dispatch_get_main_queue(), released);
                }
            }
            if (now - lastMemoryCheck > 1.0) {
                lastMemoryCheck = now;
                size_t freeNow = os_proc_available_memory();
                if (freeNow > 0 && (gSessionMinFree == 0 || freeNow < gSessionMinFree)) gSessionMinFree = freeNow;
            }
        }
    }
    // Si el depurador sigue enganchado (se salió antes de soltarlo), se suelta antes de cerrar:
    // con él puesto, el cierre del núcleo pasa por StikDebug y la VPN y tarda muchísimo.
    if (OSLRUsesJITScript() && OSLRIsTraced()) {
        OSLRTrace(@"salir: se suelta el depurador antes de cerrar", NO);
        OSLRInstallTrapGuard(YES);
        OSLRUniversalDetach();
        void (^released)(void) = self.debuggerReleasedHandler;
        if (released) dispatch_async(dispatch_get_main_queue(), released);
    }
    OSLRTrace(@"salir: guardar partida", NO);
    [self writeSaveRAMIfChanged:lastSave];
    // Como RetroArch: primero se avisa al núcleo de que se va el contexto y luego se cierra el juego.
    OSLRTrace(@"salir: context_destroy", NO);
    if ((gGLContext != nil || gVKDevice != VK_NULL_HANDLE) && gHWCallback.context_destroy) gHWCallback.context_destroy();
    OSLRTrace(@"salir: retro_unload_game", NO);
    gCore.unloadGame();
    OSLRTrace(@"salir: retro_deinit", NO);
    gCore.deinit();
    OSLRTrace(@"salir: cerrar imagen", NO);
    OSLRDestroyGL();
    OSLRDestroyVulkan();
    OSLRTrace(@"salir: listo", NO);
    atomic_store(&gLoopDone, true);
    // Lo que el núcleo no devolvió del bloque permanente vuelve al bloque (el bloque se queda).
    @synchronized (gJITSessionBlocks) {
        for (NSValue *block in gJITSessionBlocks) OSLRJITPoolFree(block.pointerValue);
        [gJITSessionBlocks removeAllObjects];
    }
    // Cuánta memoria llegó a gastar la partida (para avisar antes de la próxima si no cabe).
    if (gSessionStartFree > 0 && gSessionMinFree > 0 && gSessionStartFree > gSessionMinFree) {
        self.lastSessionPeakMB = (NSUInteger)((gSessionStartFree - gSessionMinFree) / (1024 * 1024));
    } else {
        self.lastSessionPeakMB = 0;
    }
    // Lo que el núcleo liberó se le devuelve a iOS ya (si no, el sistema lo sigue contando).
    malloc_zone_pressure_relief(NULL, 0);
    [self finishSession];
}

/// El núcleo no terminó: se cierra su pantalla y se vuelve a la app (su hilo sigue ocupado).
- (void)abandonSession {
    [_audio stop];
    _audio = nil;
    gMessageHandler = nil;
    OSLRGameViewController *controller = self.gameController;
    self.gameController = nil;
    controller.closing = YES;
    [controller releaseExternalDisplay];
    void (^done)(void) = ^{
        self.busy = NO;
        void (^ended)(void) = self.endedHandler;
        self.endedHandler = nil;
        if (ended) ended();
    };
    UIViewController *presenter = controller.presentingViewController;
    if (presenter) {
        [presenter dismissViewControllerAnimated:NO completion:done];
    } else {
        done();
    }
}

- (void)finishSession {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Terminó tarde (ya se había vuelto a la biblioteca): solo queda limpiar.
        if (atomic_load(&gCoreStuck)) {
            atomic_store(&gCoreStuck, false);
            free(gAudioRing);
            gAudioRing = NULL;
            gAudioCapacity = 0;
            self->_gameData = nil;
            gGLLayer = nil;
            gMetalLayer = nil;
            return;
        }
        [self->_audio stop];
        self->_audio = nil;
        self->_gameData = nil;
        free(gAudioRing);
        gAudioRing = NULL;
        gAudioCapacity = 0;
        gMessageHandler = nil;
        atomic_store(&gPadBits, 0);
        atomic_store(&gTouchBits, 0);
        atomic_store(&gTouchCBits, 0);
        atomic_store(&gTouchStickActive, false);
        atomic_store(&gPointerDown, false);
        gGLLayer = nil;
        gMetalLayer = nil;
        OSLRGameViewController *controller = self.gameController;
        self.gameController = nil;
        controller.closing = YES;
        [controller releaseExternalDisplay];
        void (^done)(void) = ^{
            self.busy = NO;
            void (^ended)(void) = self.endedHandler;
            self.endedHandler = nil;
            if (ended) ended();
        };
        UIViewController *presenter = controller.presentingViewController;
        if (presenter) {
            [presenter dismissViewControllerAnimated:NO completion:done];
        } else {
            done();
        }
    });
}

- (void)launchGameAtPath:(NSString *)gamePath
                   title:(NSString *)title
               framework:(NSString *)framework
                  layout:(NSString *)layout
         systemDirectory:(NSString *)systemDirectory
           saveDirectory:(NSString *)saveDirectory
             coreOptions:(NSDictionary<NSString *, NSString *> *)coreOptions
             hostOptions:(NSDictionary<NSString *, NSString *> *)hostOptions
                language:(NSString *)language
              completion:(void (^)(BOOL, NSString *))completion
                   ended:(void (^)(void))ended {
    if (self.busy) {
        completion(NO, OSLRText(language, @"Ya hay una partida abierta.", @"A game is already running."));
        return;
    }
    if (atomic_load(&gCoreStuck)) {
        completion(NO, OSLRText(language, @"El núcleo del juego anterior no terminó de cerrarse. Reabre OmniStation para jugar a estos sistemas (ARMSX2 y MeloNX siguen funcionando).",
                                @"The previous game's core did not finish closing. Reopen OmniStation to play these systems (ARMSX2 and MeloNX still work)."));
        return;
    }
    if (![NSFileManager.defaultManager isReadableFileAtPath:gamePath]) {
        completion(NO, OSLRText(language, @"No se puede leer el archivo del juego.", @"The game file cannot be read."));
        return;
    }
    NSString *error = nil;
    if (![self loadCore:framework error:&error]) {
        completion(NO, error ?: @"No se pudo cargar el núcleo.");
        return;
    }
    UIViewController *root = [self topViewController];
    if (root == nil) {
        completion(NO, @"No se pudo crear la pantalla del juego.");
        return;
    }
    self.busy = YES;
    self.endedHandler = ended;
    _language = [language copy];
    [NSFileManager.defaultManager createDirectoryAtPath:systemDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    [NSFileManager.defaultManager createDirectoryAtPath:saveDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    snprintf(gSystemDir, sizeof(gSystemDir), "%s", systemDirectory.fileSystemRepresentation);
    snprintf(gSaveDir, sizeof(gSaveDir), "%s", saveDirectory.fileSystemRepresentation);
    NSString *base = gamePath.lastPathComponent.stringByDeletingPathExtension;
    _savePath = [saveDirectory stringByAppendingPathComponent:[base stringByAppendingPathExtension:@"srm"]];
    _statePath = [saveDirectory stringByAppendingPathComponent:[base stringByAppendingPathExtension:@"state"]];
    gLanguage = [language isEqualToString:@"en"] ? RETRO_LANGUAGE_ENGLISH : RETRO_LANGUAGE_SPANISH;
    gUserOptions = [coreOptions copy] ?: @{};
    gDefaultOptions = [NSMutableDictionary new];
    gOptionValues = [NSMutableDictionary new];
    gOptionStrings = [NSMutableDictionary new];
    gPixelFormat = RETRO_PIXEL_FORMAT_0RGB1555;
    gHasFrameTimeCallback = NO;
    // JIT: solo si se pidió y OmniStation lo tiene de verdad ahora.
    gJITWanted = [hostOptions[@"jit"] isEqualToString:@"true"];
    // Núcleo que pide su memoria de JIT a OmniStation: le vale el bloque permanente aunque ya no
    // haya depurador.
    BOOL pooled = [hostOptions[@"jitPool"] isEqualToString:@"true"] && [OSLibretroEngine persistentJITReady];
    gJITCapable = gJITWanted && ([OSLibretroEngine jitActive] || pooled);
    gJITSessionBlocks = [NSMutableArray new];
    gJITPoolCore = [hostOptions[@"jitPool"] isEqualToString:@"true"];
    atomic_store(&gJITPoolGiven, false);
    atomic_store(&gJITSmallLogged, 0);
    gJITUnanswered = 0;
    atomic_store(&gLoopDone, false);
    @synchronized ([OSLibretroEngine class]) { gLastCoreMessage = nil; }
    OSLRCoreLogReset();
    OSLRTrace([NSString stringWithFormat:@"abrir: %@ con %@ (JIT %@, depurador %@)", gamePath.lastPathComponent, framework,
               [hostOptions[@"jit"] isEqualToString:@"true"] ? @"pedido" : @"no", OSLRIsTraced() ? @"enganchado" : @"no"], YES);
    gSessionStartFree = os_proc_available_memory();
    gSessionMinFree = 0;
    os_unfair_lock_lock(&gPendingLock);
    [gPendingOptions removeAllObjects];
    os_unfair_lock_unlock(&gPendingLock);
    OSLRInstallTrapGuard(NO);
    // Imagen por GPU y proporción.
    memset(&gHWCallback, 0, sizeof(gHWCallback));
    gHWRequested = false;
    gVKNegotiation = NULL;
    memset(&gDisk, 0, sizeof(gDisk));
    gHasDisk = false;
    atomic_store(&gDiskCount, 0);
    gGLSmooth = [hostOptions[@"filter"] isEqualToString:@"linear"];
    atomic_store(&gGLLayerShown, false);
    atomic_store(&gGLLayerChanged, true);
    gUseFrameAspect = [hostOptions[@"frameAspect"] isEqualToString:@"true"];
    gAspectFrameWidth = 0;
    gAspectFrameHeight = 0;
    // Opción que va con la orientación: la de ahora, desde el principio.
    gOrientKey = hostOptions[@"orient.key"].length > 0 ? [hostOptions[@"orient.key"] copy] : nil;
    gOrientPortrait = [hostOptions[@"orient.portrait"] copy];
    gOrientLandscape = [hostOptions[@"orient.landscape"] copy];
    gOrientApplied = -1;
    atomic_store(&gOrientWanted, -1);
    atomic_store(&gVariablesChanged, false);
    if (gOrientKey != nil) {
        CGSize screen = UIScreen.mainScreen.bounds.size;
        BOOL portrait = screen.height > screen.width && !(OSExternalDisplay.enabled && OSExternalDisplay.shared.connected);
        NSString *value = portrait ? gOrientPortrait : gOrientLandscape;
        if (value.length > 0) {
            NSMutableDictionary<NSString *, NSString *> *options = [gUserOptions mutableCopy];
            options[gOrientKey] = value;
            gUserOptions = options;
        }
        gOrientApplied = portrait ? 1 : 0;
        atomic_store(&gOrientWanted, gOrientApplied);
    }
    atomic_store(&gShutdownRequested, false);
    atomic_store(&gInputSuspended, false);
    atomic_store(&gFrameSerial, 0);
    atomic_store(&gFrameCount, 0);
    atomic_store(&gAspect, 4.0 / 3.0);
    atomic_store(&gPaused, false);
    atomic_store(&gBackground, false);
    atomic_store(&gPendingAction, -1);
    atomic_store(&gRunning, true);
    os_unfair_lock_lock(&gFrameLock);
    gFrameWidth = 0;
    gFrameHeight = 0;
    os_unfair_lock_unlock(&gFrameLock);

    OSLRGameViewController *controller = [OSLRGameViewController new];
    controller.language = language;
    controller.layout = layout;
    controller.title = title;
    controller.touchAlways = [hostOptions[@"touchAlways"] boolValue];
    controller.touchHaptics = [hostOptions[@"touchHaptics"] boolValue];
    controller.stretch = [hostOptions[@"aspect"] isEqualToString:@"stretch"];
    controller.smooth = [hostOptions[@"filter"] isEqualToString:@"linear"];
    controller.pointer = ([layout isEqualToString:@"nds"] || [layout isEqualToString:@"3ds"]) && ![hostOptions[@"touchPointer"] isEqualToString:@"false"];
    // Si el núcleo puede ir con o sin JIT, el menú dice cómo arrancó.
    if ([hostOptions[@"jitOption"] isEqualToString:@"true"]) {
        controller.jitOn = gJITCapable;
        if (gJITCapable) {
            controller.jitText = OSLRText(language, @"Con JIT", @"Running with JIT");
        } else if (![hostOptions[@"jit"] isEqualToString:@"true"]) {
            controller.jitText = OSLRText(language, @"Sin JIT: desactivado en sus ajustes", @"No JIT: turned off in its settings");
        } else if (OSLRUsesJITScript() && OSLRIsDebugged() && !OSLRIsTraced()) {
            controller.jitText = OSLRText(language, @"Sin JIT: hay JIT pero el depurador ya no está enganchado (desde iOS 26 hace falta)", @"No JIT: JIT was enabled but the debugger is no longer attached (iOS 26 and later need it)");
        } else {
            controller.jitText = OSLRText(language, @"Sin JIT (modo intérprete)", @"No JIT (interpreter mode)");
        }
    }
    NSMutableDictionary<NSNumber *, NSNumber *> *map = [NSMutableDictionary new];
    for (NSString *key in hostOptions) {
        if (![key hasPrefix:@"map."]) continue;
        int from = OSLRRetroButtonForMapID([key substringFromIndex:4]);
        int to = OSLRRetroButtonForMapID(hostOptions[key]);
        if (from >= 0 && to >= 0) map[@(from)] = @(to);
    }
    controller.buttonMap = map;
    // Opciones del núcleo para el menú de la partida (con el valor con el que arranca).
    controller.coreOptions = OSLRMenuOptions(self.menuOptions);
    void (^changed)(NSString *, NSString *) = self.menuOptionChanged;
    controller.optionChanged = ^(NSString *key, NSString *value) {
        if (changed) changed(key, value);
    };
    if ([hostOptions[@"hud"] boolValue]) {
        OSPerfHUD *hud = [[OSPerfHUD alloc] initWithFrame:CGRectZero];
        hud.showFrameTime = NO;
        hud.showFifo = NO;
        hud.showMemory = ![hostOptions[@"hudMemory"] isEqualToString:@"false"];
        hud.showThermal = ![hostOptions[@"hudThermal"] isEqualToString:@"false"];
        hud.showBattery = [hostOptions[@"hudBattery"] boolValue];
        controller.hud = hud;
    }
    __weak OSLibretroEngine *weakSelf = self;
    __weak OSLRGameViewController *weakController = controller;
    controller.menuChanged = ^(BOOL open) {
        OSLibretroEngine *strongSelf = weakSelf;
        if (!strongSelf) return;
        atomic_store(&gPaused, open);
        atomic_store(&gInputSuspended, open);
    };
    controller.menuAction = ^(NSInteger action) {
        OSLibretroEngine *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (action == OSLRMenuActionQuit) {
            OSLRTrace(@"salir: pedido", NO);
            weakController.closing = YES;
            atomic_store(&gRunning, false);
            atomic_store(&gPaused, false);
            // Si el núcleo no termina de cerrarse, la app no se queda colgada en su pantalla: se
            // vuelve a la biblioteca y se avisa (ese núcleo queda ocupado hasta reabrir la app).
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                OSLibretroEngine *engine = weakSelf;
                if (engine == nil || !engine.busy || atomic_load(&gLoopDone)) return;
                OSLRTrace(@"salir: el núcleo no terminó en 12 s; se vuelve a la biblioteca", NO);
                atomic_store(&gCoreStuck, true);
                [engine abandonSession];
            });
            return;
        }
        if (action != OSLRMenuActionResume) atomic_store(&gPendingAction, (int)action);
    };
    gMessageHandler = ^(NSString *message) {
        [weakController showStatus:message];
    };
    [controller loadViewIfNeeded];
    gGLLayer = nil;
    gMetalLayer = nil;
    if ([hostOptions[@"gpu"] isEqualToString:@"true"]) {
        [controller.videoView enableGLLayer];
        gGLLayer = controller.videoView.glLayer;
    } else if ([hostOptions[@"gpu"] isEqualToString:@"vulkan"]) {
        [controller.videoView enableMetalLayer];
        gMetalLayer = controller.videoView.metalLayer;
    }
    [root presentViewController:controller animated:NO completion:nil];
    self.gameController = controller;

    NSThread *thread = [[NSThread alloc] initWithBlock:^{
        [self emulationLoopWithFramework:framework gamePath:gamePath completion:^(BOOL success, NSString *message) {
            if (success) {
                BOOL physical = GCController.current.extendedGamepad != nil;
                [weakController showStatus:physical ? OSLRText(language, @"Home o SELECT+START: menú", @"Home or SELECT+START: menu")
                                                    : OSLRText(language, @"Botón ☰: menú", @"☰ button: menu")];
            }
            completion(success, message);
        }];
    }];
    thread.name = @"OmniStation libretro";
    thread.stackSize = 8 * 1024 * 1024;
    thread.qualityOfService = NSQualityOfServiceUserInteractive;
    _thread = thread;
    [thread start];
}

@end
