// Estructura de opciones de MeloNX 2.7 (main_ryujinx_sdl), copiada tal cual de
// src/MeloNX/MeloNX/Core/Models/Options/NativeOptions.h de MeloNX (AGPL-3.0, Stossy11).
// Solo la usa OSMeloNXEngine.m: no se expone a Swift (sus nombres chocarían).
// No cambies el orden ni los tipos: tiene que coincidir byte a byte con el núcleo.
#pragma once

#include <stdbool.h>
#include <stdint.h>

typedef enum __attribute__((enum_extensibility(open))) SystemLanguage {
    SystemLanguage_Japanese              = 0,
    SystemLanguage_AmericanEnglish       = 1,
    SystemLanguage_French                = 2,
    SystemLanguage_German                = 3,
    SystemLanguage_Italian               = 4,
    SystemLanguage_Spanish               = 5,
    SystemLanguage_Chinese               = 6,
    SystemLanguage_Korean                = 7,
    SystemLanguage_Dutch                 = 8,
    SystemLanguage_Portuguese            = 9,
    SystemLanguage_Russian               = 10,
    SystemLanguage_Taiwanese             = 11,
    SystemLanguage_BritishEnglish        = 12,
    SystemLanguage_CanadianFrench        = 13,
    SystemLanguage_LatinAmericanSpanish  = 14,
    SystemLanguage_SimplifiedChinese     = 15,
    SystemLanguage_TraditionalChinese    = 16,
    SystemLanguage_BrazilianPortuguese   = 17,
    SystemLanguage_Polish                = 18,
    SystemLanguage_Thai                  = 19,
} SystemLanguage;

typedef enum __attribute__((enum_extensibility(open))) HideCursorMode {
    HideCursorMode_Never  = 0,
    HideCursorMode_OnIdle = 1,
    HideCursorMode_Always = 2,
} HideCursorMode;

typedef enum __attribute__((enum_extensibility(open))) NativeRegionCode {
    NativeRegionCode_Japan     = 0,
    NativeRegionCode_USA       = 1,
    NativeRegionCode_Europe    = 2,
    NativeRegionCode_Australia = 3,
    NativeRegionCode_China     = 4,
    NativeRegionCode_Korea     = 5,
    NativeRegionCode_Taiwan    = 6,

    NativeRegionCode_Min = NativeRegionCode_Japan,
    NativeRegionCode_Max = NativeRegionCode_Taiwan,
} NativeRegionCode;

/* MemoryManagerMode has a byte backing type in C# */
typedef enum __attribute__((enum_extensibility(open))) MemoryManagerMode : uint8_t {
    MemoryManagerMode_SoftwarePageTable = 0,
    MemoryManagerMode_HostMapped        = 1,
    MemoryManagerMode_HostMappedUnsafe  = 2,
} MemoryManagerMode;

typedef enum __attribute__((enum_extensibility(open))) GraphicsDebugLevel {
    GraphicsDebugLevel_None      = 0,
    GraphicsDebugLevel_Error     = 1,
    GraphicsDebugLevel_Slowdowns = 2,
    GraphicsDebugLevel_All       = 3,
} GraphicsDebugLevel;

/* ControllerType is a [Flags] enum */
typedef enum __attribute__((flag_enum, enum_extensibility(open))) ControllerType {
    ControllerTypeNone           = 0,
    ControllerTypeProController  = 1 << 0,
    ControllerTypeHandheld       = 1 << 1,
    ControllerTypeJoyconPair     = 1 << 2,
    ControllerTypeJoyconLeft     = 1 << 3,
    ControllerTypeJoyconRight    = 1 << 4,
    ControllerTypeInvalid        = 1 << 5,
    ControllerTypePokeball       = 1 << 6,
    ControllerTypeSystemExternal = 1 << 29,
    ControllerTypeSystem         = 1 << 30,
} ControllerType;

typedef enum __attribute__((enum_extensibility(open))) AspectRatio {
    AspectRatio_Fixed4x3  = 0,
    AspectRatio_Fixed16x9 = 1,
    AspectRatio_Fixed16x10 = 2,
    AspectRatio_Fixed21x9 = 3,
    AspectRatio_Fixed32x9 = 4,
    AspectRatio_Stretched = 5,
} AspectRatio;

typedef enum __attribute__((enum_extensibility(open))) BackendThreading {
    BackendThreading_Auto = 0,
    BackendThreading_Off  = 1,
    BackendThreading_On   = 2,
} BackendThreading;

typedef enum __attribute__((enum_extensibility(open))) AntiAliasing {
    AntiAliasing_None       = 0,
    AntiAliasing_Fxaa       = 1,
    AntiAliasing_SmaaLow    = 2,
    AntiAliasing_SmaaMedium = 3,
    AntiAliasing_SmaaHigh   = 4,
    AntiAliasing_SmaaUltra  = 5,
} AntiAliasing;

typedef enum __attribute__((enum_extensibility(open))) ScalingFilter {
    ScalingFilter_Bilinear = 0,
    ScalingFilter_Nearest  = 1,
    ScalingFilter_Fsr      = 2,
    ScalingFilter_Area     = 3,
    ScalingFilter_MetalFx  = 4,
} ScalingFilter;

typedef enum __attribute__((enum_extensibility(open))) GraphicsBackend {
    GraphicsBackend_Vulkan = 0,
    GraphicsBackend_OpenGl = 1,
} GraphicsBackend;

typedef struct OptionsNative {
    char*  BaseDataDir;
    char*  UserProfile;
    int32_t DisplayId;
    bool   IsFullscreen;
    bool   IsExclusiveFullscreen;
    int32_t ExclusiveFullscreenWidth;
    int32_t ExclusiveFullscreenHeight;

    char*  DeviceModel;
    bool   MemoryEnt;
    char*  DisplayName;

    bool   OnScreenCorrespond;

    char*  InputProfile1Name;
    char*  InputProfile2Name;
    char*  InputProfile3Name;
    char*  InputProfile4Name;
    char*  InputProfile5Name;
    char*  InputProfile6Name;
    char*  InputProfile7Name;
    char*  InputProfile8Name;
    char*  InputProfileHandheldName;

    ControllerType ControllerType1;
    ControllerType ControllerType2;
    ControllerType ControllerType3;
    ControllerType ControllerType4;
    ControllerType ControllerType5;
    ControllerType ControllerType6;
    ControllerType ControllerType7;
    ControllerType ControllerType8;

    char*  InputId1;
    char*  InputId2;
    char*  InputId3;
    char*  InputId4;
    char*  InputId5;
    char*  InputId6;
    char*  InputId7;
    char*  InputId8;
    char*  InputIdHandheld;

    char*  InputDSUServer1;
    char*  InputDSUServer2;
    char*  InputDSUServer3;
    char*  InputDSUServer4;
    char*  InputDSUServer5;
    char*  InputDSUServer6;
    char*  InputDSUServer7;
    char*  InputDSUServer8;
    char*  InputDSUServerHandheld;

    bool   EnableKeyboard;
    bool   EnableMouse;
    HideCursorMode HideCursorMode;
    bool   ListInputProfiles;
    bool   ListInputIds;

    bool   DisablePTC;
    bool   EnableInternetAccess;
    bool   DisableFsIntegrityChecks;
    int32_t FsGlobalAccessLogMode;
    bool   DisableVSync;
    int32_t VSyncMode;
    int32_t CustomVSyncInterval;
    bool   DisableShaderCache;
    bool   EnableTextureRecompression;
    bool   DisableDockedMode;
    SystemLanguage    SystemLanguage;
    NativeRegionCode        SystemRegion;
    char*             SystemTimeZone;
    int64_t           SystemTimeOffset;
    MemoryManagerMode MemoryManagerMode;
    float  AudioVolume;
    bool   UseHypervisor;
    bool   LdnMitm;
    char*  MultiplayerLanInterfaceId;
    char*  MultiplayerLanInterfaceAddress;
    char*  MultiplayerLanInterfaceSubnetMask;

    bool   DisableFileLog;
    bool   LoggingEnableDebug;
    bool   LoggingDisableStub;
    bool   LoggingDisableInfo;
    bool   LoggingDisableWarning;
    bool   LoggingEnableError;
    bool   LoggingEnableTrace;
    bool   LoggingDisableGuest;
    bool   LoggingEnableFsAccessLog;
    GraphicsDebugLevel LoggingGraphicsDebugLevel;

    float  ResScale;
    float  MaxAnisotropy;
    AspectRatio      AspectRatio;
    BackendThreading BackendThreading;
    bool   EnableAsyncShaderCompilation;
    bool   DisableMacroHLE;
    char*  GraphicsShadersDumpPath;
    GraphicsBackend  GraphicsBackend;
    char*  PreferredGPUVendor;
    AntiAliasing  AntiAliasing;
    ScalingFilter ScalingFilter;
    int32_t ScalingFilterLevel;
    float MetalFxUpscaleFactor;
    bool   EnableHostMemoryBudgetTracking;

    bool   ExpandRAM;
    bool   IgnoreMissingServices;

    char*  InputPath;
} OptionsNative;
