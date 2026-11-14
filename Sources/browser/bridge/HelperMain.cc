#include "include/cef_app.h"
#include "include/cef_sandbox_mac.h"
#include "include/wrapper/cef_library_loader.h"
int main(int argc, char **argv) {
  CefScopedSandboxContext sandbox;
  if (!sandbox.Initialize(argc, argv)) return 20;
  CefScopedLibraryLoader loader;
  if (!loader.LoadInHelper()) return 21;
  return CefExecuteProcess(CefMainArgs(argc, argv), nullptr, nullptr);
}
