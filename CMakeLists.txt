cmake_minimum_required(VERSION 3.25)
set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING "Development deployment target")
set(JENA_ENGINE "WEBKIT" CACHE STRING "Web engine: WEBKIT (system WebKit, product default) or CEF (legacy)")
if(JENA_ENGINE STREQUAL "CEF")
  project(JenaWeb LANGUAGES C CXX OBJCXX Swift)
else()
  project(JenaWeb LANGUAGES Swift)
endif()
if(NOT APPLE)
  message(FATAL_ERROR "Jena Web currently targets macOS only")
endif()
set(COMMON_SOURCES
  Sources/app/JenaWebMain.swift Sources/app/AppComposition.swift
  Sources/workspace/BrowserWindowController.swift
  Sources/browser/contracts/BrowserRuntime.swift
  Sources/tabs/TabService.swift Sources/search/SearchService.swift
  Sources/settings/AppSettings.swift Sources/storage/AppDatabase.swift
  Sources/bookmarks/Bookmark.swift Sources/bookmarks/BookmarksWindowController.swift
  Sources/history/HistoryService.swift Sources/history/HistoryWindowController.swift
  Sources/site-settings/SiteSettingsService.swift Sources/site-settings/SiteSettingsWindowController.swift
  Sources/platform/macos/SystemPermissions.swift
  Sources/privacy/PrivacyService.swift Sources/privacy/PrivacyWindowController.swift
  Sources/navigation/NavigationService.swift Sources/platform/macos/AppPaths.swift)
if(NOT JENA_ENGINE STREQUAL "CEF")
  # System WebKit: no engine download, no helper processes to package.
  set(CMAKE_Swift_LANGUAGE_VERSION 6)
  set(CMAKE_XCODE_ATTRIBUTE_SWIFT_VERSION 6.0)
  add_executable(JenaWeb MACOSX_BUNDLE ${COMMON_SOURCES} Sources/browser/webkit/WebKitBrowserRuntime.swift
    Resources/search-providers.json Resources/link-policy.js Resources/JenaWeb.icns)
  set_source_files_properties(Resources/search-providers.json Resources/link-policy.js Resources/JenaWeb.icns PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
  set_target_properties(JenaWeb PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Configuration/App-Info-WebKit.plist"
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "local.jena.web"
    XCODE_GENERATE_SCHEME YES)
  target_link_libraries(JenaWeb PRIVATE "-framework AppKit" "-framework WebKit" "-framework AVFoundation" "-framework CoreLocation" "-lsqlite3")
  # Ad-hoc signature gives the app a stable identity for macOS camera/microphone consent.
  add_custom_command(TARGET JenaWeb POST_BUILD
    COMMAND codesign --force --sign - "$<TARGET_BUNDLE_DIR:JenaWeb>" VERBATIM)
  return()
endif()
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_OBJCXX_STANDARD 20)
set(CMAKE_Swift_LANGUAGE_VERSION 6)
set(CMAKE_XCODE_ATTRIBUTE_SWIFT_VERSION 6.0)
set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO)
set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING "Development deployment target")
set(CEF_ROOT "" CACHE PATH "Path to the existing pinned CEF binary distribution")
if(NOT EXISTS "${CEF_ROOT}/cmake/FindCEF.cmake")
  message(FATAL_ERROR "Set CEF_ROOT to the installed CEF distribution; see BuildSupport/README.md")
endif()
find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(CEF_INPUT_LOCK "${CMAKE_CURRENT_BINARY_DIR}/cef-input-lock.json")
execute_process(
  COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/BuildSupport/cef_identity.py"
    --cef-root "${CEF_ROOT}" --lock "${CEF_INPUT_LOCK}"
  RESULT_VARIABLE CEF_LOCK_RESULT)
if(NOT CEF_LOCK_RESULT EQUAL 0)
  message(FATAL_ERROR "CEF input lock failed. Preserve existing output and use a new build directory.")
endif()
list(APPEND CMAKE_MODULE_PATH "${CEF_ROOT}/cmake")
set(USE_SANDBOX ON CACHE BOOL "CEF sandbox" FORCE)
find_package(CEF REQUIRED)
# CEF clears the identity globally; Xcode command-line targets require a value.
set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "-")
set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO)
add_subdirectory("${CEF_ROOT}/libcef_dll" "cef-wrapper")
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/Resources/link-policy.js" LINK_SCRIPT)
configure_file("BuildSupport/NavigationLinkScript.h.in" "generated/NavigationLinkScript.h" @ONLY)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "Resources/link-policy.js")
add_library(CEFBridge STATIC Sources/browser/bridge/JenaBridge.mm)
target_include_directories(CEFBridge PRIVATE "${CEF_ROOT}" "${CMAKE_CURRENT_BINARY_DIR}/generated")
target_compile_definitions(CEFBridge PRIVATE CEF_USE_SANDBOX)
target_compile_options(CEFBridge PRIVATE -fobjc-arc)
target_link_libraries(CEFBridge PUBLIC libcef_dll_wrapper "-framework AppKit" "-framework AVFoundation")

add_executable(JenaWebHelper Sources/browser/bridge/HelperMain.cc)
target_include_directories(JenaWebHelper PRIVATE "${CEF_ROOT}")
target_compile_definitions(JenaWebHelper PRIVATE CEF_USE_SANDBOX)
target_link_libraries(JenaWebHelper PRIVATE libcef_dll_wrapper "-framework AppKit")

set(APP_SOURCES ${COMMON_SOURCES} Sources/browser/cef/CEFBrowserRuntime.swift)
add_executable(JenaWeb MACOSX_BUNDLE ${APP_SOURCES} Resources/search-providers.json)
set_source_files_properties(Resources/search-providers.json PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
set_target_properties(JenaWeb PROPERTIES
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Configuration/App-Info.plist"
  XCODE_ATTRIBUTE_SWIFT_OBJC_BRIDGING_HEADER "${CMAKE_CURRENT_SOURCE_DIR}/Sources/browser/bridge/JenaBridge.h"
  XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO
  XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "local.jena.web"
  XCODE_GENERATE_SCHEME YES)
if(NOT CMAKE_GENERATOR STREQUAL "Xcode")
  target_compile_options(JenaWeb PRIVATE -import-objc-header "${CMAKE_CURRENT_SOURCE_DIR}/Sources/browser/bridge/JenaBridge.h")
endif()
target_link_libraries(JenaWeb PRIVATE CEFBridge "-framework AppKit" "-lc++" "-lsqlite3")
add_dependencies(JenaWeb JenaWebHelper)
add_custom_command(TARGET JenaWeb POST_BUILD
  COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/BuildSupport/package_app.py"
    --app "$<TARGET_BUNDLE_DIR:JenaWeb>" --helper "$<TARGET_FILE:JenaWebHelper>"
    --cef-root "${CEF_ROOT}" --cef-lock "${CEF_INPUT_LOCK}" --configuration "${CMAKE_CURRENT_SOURCE_DIR}/Configuration"
  VERBATIM)
