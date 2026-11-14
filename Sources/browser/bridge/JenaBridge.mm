#import "JenaBridge.h"
#import <AVFoundation/AVFoundation.h>
#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_client.h"
#include "include/cef_parser.h"
#include "include/cef_task.h"
#include "include/cef_devtools_message_observer.h"
#include "include/wrapper/cef_library_loader.h"
#include "include/wrapper/cef_helpers.h"
#include "NavigationLinkScript.h"
#include <map>
#include <set>
#include <functional>
#include <vector>
#include <memory>

@interface JenaApplication : NSApplication <CefAppProtocol>
@property(nonatomic) BOOL handlingSendEvent;
@end
@implementation JenaApplication
- (BOOL)isHandlingSendEvent { return self.handlingSendEvent; }
- (void)sendEvent:(NSEvent *)event { CefScopedSendingEvent scope; [super sendEvent:event]; }
- (void)terminate:(id)sender { JWRequestQuit(); }
@end

namespace {
id<JWBrowserDelegate> ui;
bool quitting = false;
bool privacyBusy = false;
bool linksInNewTabs = false;
int64_t nextPage = 0;
class PageClient;
std::map<int64_t, CefRefPtr<PageClient>> pages;
std::map<std::pair<int, int>, int64_t> pendingPopups;
NSString *Text(const CefString &value) { return [NSString stringWithUTF8String:value.ToString().c_str()] ?: @""; }
bool WebURL(const std::string &url) { return url.starts_with("https://") || url.starts_with("http://") || url == "about:blank"; }
class Task final : public CefTask {
 public:
  explicit Task(std::function<void()> action) : action_(std::move(action)) {}
  void Execute() override { action_(); }
 private:
  std::function<void()> action_;
  IMPLEMENT_REFCOUNTING(Task);
};
void ContinueQuit();
void MaybeQuit() { if (quitting && pages.empty()) CefQuitMessageLoop(); }
void RemovePage(int64_t id) { pages.erase(id); [ui pageClosed:id]; ContinueQuit(); }

class PageClient final : public CefClient, public CefLifeSpanHandler,
    public CefDisplayHandler, public CefLoadHandler, public CefRequestHandler,
    public CefJSDialogHandler, public CefPermissionHandler, public CefDevToolsMessageObserver {
 public:
  PageClient(int64_t id, NSView *host) : id_(id), host_(host) {}
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  CefRefPtr<CefJSDialogHandler> GetJSDialogHandler() override { return this; }
  CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    browser_ = browser;
    for (auto it = pendingPopups.begin(); it != pendingPopups.end();) {
      if (it->second == id_) it = pendingPopups.erase(it); else ++it;
    }
    NSView *view = (__bridge NSView *)browser->GetHost()->GetWindowHandle();
    view.frame = host_.bounds;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    observer_ = browser->GetHost()->AddDevToolsMessageObserver(this);
    [ui pageCreated:id_];
    if (quitting || closeRequested_) { browser->GetHost()->CloseBrowser(false); return; }
    InstallPolicy("");
    auto params = CefDictionaryValue::Create();
    params->SetBool("autoAttach", true); params->SetBool("waitForDebuggerOnStart", true); params->SetBool("flatten", true);
    auto filters = CefListValue::Create(); auto iframe = CefDictionaryValue::Create();
    iframe->SetString("type", "iframe"); iframe->SetBool("exclude", false); filters->SetDictionary(0, iframe);
    auto other = CefDictionaryValue::Create(); other->SetBool("exclude", true); filters->SetDictionary(1, other);
    params->SetList("filter", filters); Command("Target.setAutoAttach", params, "", [this](auto result) { ReportProtocolError(result); });
  }
  void Navigate(const std::string &url) {
    if (privacyBusy) { [ui page:id_ failed:@"웹 데이터 삭제 중에는 탐색할 수 없습니다."]; return; }
    if (!WebURL(url)) { [ui page:id_ failed:@"HTTP 또는 HTTPS 주소만 열 수 있습니다."]; return; }
    if (browser_) browser_->GetMainFrame()->LoadURL(url);
  }
  void Action(int action) {
    if (privacyBusy) return;
    if (action == 4) closeRequested_ = true;
    if (!browser_) return;
    switch (action) {
      case 0: browser_->GoBack(); break;
      case 1: browser_->GoForward(); break;
      case 2: browser_->Reload(); break;
      case 3: browser_->StopLoad(); break;
      case 4: browser_->GetHost()->CloseBrowser(false); break;
    }
  }
  void OnBeforeClose(CefRefPtr<CefBrowser>) override {
    observer_ = nullptr; replies_.clear(); browser_ = nullptr;
    CefRefPtr<PageClient> keepAlive = this;
    RemovePage(id_);
  }
  bool DoClose(CefRefPtr<CefBrowser> browser) override {
    NSView *view = (__bridge NSView *)browser->GetHost()->GetWindowHandle();
    [view removeFromSuperview];
    return false;
  }
  void OnTitleChange(CefRefPtr<CefBrowser>, const CefString &title) override { title_ = Text(title); [ui page:id_ titleChanged:title_]; }
  void OnAddressChange(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, const CefString &url) override {
    if (frame->IsMain()) [ui page:id_ addressChanged:Text(url)];
  }
  void OnLoadingStateChange(CefRefPtr<CefBrowser>, bool loading, bool back, bool forward) override {
    [ui page:id_ loading:loading back:back forward:forward];
  }
  void OnLoadEnd(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, int status) override {
    auto url = frame->GetURL().ToString();
    if (frame->IsMain() && status >= 200 && status < 400 && (url.starts_with("https://") || url.starts_with("http://"))) {
      [ui page:id_ visitedURL:Text(frame->GetURL()) title:title_ ?: @""];
    }
  }
  void OnLoadError(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, ErrorCode code,
                   const CefString &message, const CefString &) override {
    if (frame->IsMain() && code != ERR_ABORTED) [ui page:id_ failed:Text(message)];
  }
  bool OnBeforeBrowse(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame,
                      CefRefPtr<CefRequest> request, bool, bool) override {
    if (privacyBusy) return true;
    // Preserve forms, redirects and same-document moves; do not reissue them as GET.
    if (frame->IsMain() && !WebURL(request->GetURL().ToString())) {
      [ui page:id_ failed:@"이 링크 유형은 아직 앱에서 지원하지 않습니다."]; return true;
    }
    return false;
  }
  bool OnOpenURLFromTab(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, const CefString &url,
                       WindowOpenDisposition disposition, bool gesture) override {
    if (privacyBusy) return true;
    if (!gesture || !WebURL(url.ToString())) return false;
    if (disposition != CEF_WOD_NEW_FOREGROUND_TAB && disposition != CEF_WOD_NEW_BACKGROUND_TAB && disposition != CEF_WOD_NEW_WINDOW) return false;
    auto target = url.ToString(); bool foreground = disposition != CEF_WOD_NEW_BACKGROUND_TAB;
    CefPostTask(TID_UI, new Task([target, foreground] { JWCreatePage(target.c_str(), foreground); }));
    return true;
  }
  bool OnBeforePopup(CefRefPtr<CefBrowser> parent, CefRefPtr<CefFrame>, int popupID,
      const CefString &target, const CefString &, WindowOpenDisposition disposition, bool gesture,
      const CefPopupFeatures &, CefWindowInfo &window, CefRefPtr<CefClient> &client,
      CefBrowserSettings &, CefRefPtr<CefDictionaryValue> &, bool *) override {
    if (quitting || privacyBusy) return true;
    if (!target.empty() && !WebURL(target.ToString())) {
      [ui page:id_ failed:@"지원하지 않는 주소의 팝업을 차단했습니다."]; return true;
    }
    // A delayed OAuth popup may have lost transient user activation. Honor the
    // opener site's explicit popup permission without rebuilding its URL as GET.
    auto top = parent->GetMainFrame()->GetURL();
    auto context = parent->GetHost()->GetRequestContext();
    if (!gesture && context->GetContentSetting(top, top, CEF_CONTENT_SETTING_TYPE_POPUPS) != CEF_CONTENT_SETTING_VALUE_ALLOW) {
      [ui page:id_ failed:@"팝업을 차단했습니다. 현재 사이트 설정(⌘,)에서 팝업을 허용한 뒤 로그인 버튼을 다시 눌러주세요."];
      return true;
    }
    const int64_t id = ++nextPage;
    NSView *host = [ui hostForPage:id foreground:disposition != CEF_WOD_NEW_BACKGROUND_TAB];
    auto child = new PageClient(id, host); pages[id] = child;
    pendingPopups[{parent->GetIdentifier(), popupID}] = id;
    window.SetAsChild((__bridge CefWindowHandle)host, CefRect(0, 0, host.bounds.size.width, host.bounds.size.height));
    window.runtime_style = CEF_RUNTIME_STYLE_ALLOY; client = child;
    return false; // CEF keeps POST/opener/authentication context in the managed browser.
  }
  void OnBeforePopupAborted(CefRefPtr<CefBrowser> browser, int popupID) override {
    auto it = pendingPopups.find({browser->GetIdentifier(), popupID});
    if (it != pendingPopups.end()) { auto id = it->second; pendingPopups.erase(it); RemovePage(id); }
  }
  bool OnBeforeUnloadDialog(CefRefPtr<CefBrowser>, const CefString &, bool,
                            CefRefPtr<CefJSDialogCallback> callback) override {
    NSAlert *alert = [NSAlert new]; alert.messageText = @"이 페이지를 떠나시겠습니까?";
    alert.informativeText = @"저장하지 않은 입력 내용이 사라질 수 있습니다.";
    [alert addButtonWithTitle:@"떠나기"]; [alert addButtonWithTitle:@"머무르기"];
    CefRefPtr<PageClient> self = this;
    [alert beginSheetModalForWindow:host_.window completionHandler:^(NSModalResponse result) {
      bool leave = result == NSAlertFirstButtonReturn;
      if (!leave) { self->closeRequested_ = false; quitting = false; [ui terminationCancelled]; }
      callback->Continue(leave, CefString());
    }];
    return true;
  }
  bool OnRequestMediaAccessPermission(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, const CefString &origin,
      uint32_t permissions, CefRefPtr<CefMediaAccessCallback> callback) override {
    // An iframe refusal must never alter any stored origin policy.
    const uint32_t supported = CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE | CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE;
    if (!frame || !frame->IsMain() || privacyBusy || quitting || !permissions || (permissions & ~supported)) {
      callback->Cancel(); return true;
    }
    auto context = browser->GetHost()->GetRequestContext();
    auto top = browser->GetMainFrame()->GetURL();
    bool allowed = true;
    if (permissions & CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE) {
      allowed &= context->GetContentSetting(origin, top, CEF_CONTENT_SETTING_TYPE_MEDIASTREAM_MIC) == CEF_CONTENT_SETTING_VALUE_ALLOW;
      allowed &= [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] == AVAuthorizationStatusAuthorized;
    }
    if (permissions & CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE) {
      allowed &= context->GetContentSetting(origin, top, CEF_CONTENT_SETTING_TYPE_MEDIASTREAM_CAMERA) == CEF_CONTENT_SETTING_VALUE_ALLOW;
      allowed &= [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] == AVAuthorizationStatusAuthorized;
    }
    if (allowed) callback->Continue(permissions);
    else {
      callback->Cancel();
      [ui page:id_ failed:@"카메라·마이크 요청을 보류했습니다. 사이트 설정에서 사이트 허용과 macOS 권한을 확인한 뒤 다시 요청해주세요."];
    }
    return true;
  }
  bool OnShowPermissionPrompt(CefRefPtr<CefBrowser>, uint64_t, const CefString &, uint32_t,
                              CefRefPtr<CefPermissionPromptCallback> callback) override {
    // Unconfigured requests remain dismissed; explicit grants are managed in site settings.
    callback->Continue(CEF_PERMISSION_RESULT_DISMISS);
    [ui page:id_ failed:@"권한 요청을 보류했습니다. 사이트 설정에서 허용 여부를 선택한 뒤 다시 요청해주세요."];
    return true;
  }
  void RefreshPolicy() {
    InstallPolicy("");
    auto sessions = sessions_;
    for (const auto &session : sessions) InstallPolicy(session);
  }
  bool IsIdleBlank() const {
    return browser_ && !browser_->IsLoading() && browser_->GetMainFrame()->GetURL() == "about:blank";
  }
  using DeletionSteps = std::vector<std::pair<std::string, CefRefPtr<CefDictionaryValue>>>;
  void DeleteStep(std::shared_ptr<DeletionSteps> steps, size_t index, JWPrivacyCompletion completion) {
    if (index == steps->size()) {
      privacyBusy = false; completion(YES, @"선택한 웹 데이터: 삭제 요청 처리 완료"); return;
    }
    const auto &step = (*steps)[index];
    Command(step.first, step.second, "", [this, steps, index, completion](auto result) {
      if (result->HasKey("error")) {
        privacyBusy = false;
        completion(NO, [NSString stringWithFormat:@"웹 데이터 삭제 일부 실패: %lu개 작업 완료. 실패 이후 작업은 실행하지 않았습니다.", index]);
        return;
      }
      DeleteStep(steps, index + 1, completion);
    });
  }
  void DeleteWebData(NSString *origin, NSString *domain, bool cache, JWPrivacyCompletion completion) {
    auto steps = std::make_shared<DeletionSteps>();
    auto finishPlan = [this, steps, origin, cache, completion] {
      if (origin.length) {
        auto params = CefDictionaryValue::Create(); params->SetString("origin", origin.UTF8String);
        params->SetString("storageTypes", "local_storage,indexeddb,cache_storage,service_workers");
        steps->push_back({"Storage.clearDataForOrigin", params});
      }
      if (cache) steps->push_back({"Network.clearBrowserCache", CefDictionaryValue::Create()});
      DeleteStep(steps, 0, completion);
    };
    if (!origin.length) { finishPlan(); return; }
    Command("Storage.getCookies", CefDictionaryValue::Create(), "", [steps, domain, completion, finishPlan](auto response) {
      auto result = response->GetDictionary("result");
      if (response->HasKey("error") || !result || !result->HasKey("cookies")) {
        privacyBusy = false; completion(NO, @"쿠키 목록을 읽지 못해 삭제를 시작하지 않았습니다."); return;
      }
      auto cookies = result->GetList("cookies");
      for (size_t i = 0; i < cookies->GetSize(); ++i) {
        auto cookie = cookies->GetDictionary(i);
        NSString *owner = Text(cookie->GetString("domain")).lowercaseString;
        if ([owner hasPrefix:@"."]) owner = [owner substringFromIndex:1];
        if (![owner isEqual:domain] && ![owner hasSuffix:[@"." stringByAppendingString:domain]]) continue;
        if (cookie->GetBool("partitionKeyOpaque")) {
          privacyBusy = false; completion(NO, @"불투명 파티션 쿠키는 안전하게 구분할 수 없어 삭제를 시작하지 않았습니다."); return;
        }
        auto tuple = CefDictionaryValue::Create();
        for (const char *key : {"name", "domain", "path"}) tuple->SetString(key, cookie->GetString(key));
        if (cookie->HasKey("partitionKey")) tuple->SetValue("partitionKey", cookie->GetValue("partitionKey")->Copy());
        steps->push_back({"Network.deleteCookies", tuple});
      }
      finishPlan();
    });
  }
 private:
  using Reply = std::function<void(CefRefPtr<CefDictionaryValue>)>;
  void ReportProtocolError(CefRefPtr<CefDictionaryValue> response) {
    if (response->HasKey("error")) [ui page:id_ failed:@"탭 열기 정책을 적용하지 못했습니다. 페이지를 다시 열어주세요."];
  }
  void Command(const std::string &method, CefRefPtr<CefDictionaryValue> params,
               const std::string &session, Reply reply) {
    if (!browser_) return;
    int id = ++commandID_; replies_[id] = std::move(reply);
    auto request = CefDictionaryValue::Create(); request->SetInt("id", id);
    request->SetString("method", method); request->SetDictionary("params", params);
    if (!session.empty()) request->SetString("sessionId", session);
    auto value = CefValue::Create(); value->SetDictionary(request);
    auto encoded = CefWriteJSON(value, JSON_WRITER_DEFAULT).ToString();
    if (!browser_->GetHost()->SendDevToolsMessage(encoded.data(), encoded.size())) {
      auto failure = CefDictionaryValue::Create(); failure->SetString("error", "dispatch-failed");
      auto completion = std::move(replies_[id]); replies_.erase(id); completion(failure);
    }
  }
  void InstallPolicy(const std::string &session) {
    if (!browser_) return;
    Command("Page.enable", CefDictionaryValue::Create(), session, [this, session](auto response) {
      ReportProtocolError(response);
      if (response->HasKey("error")) { Resume(session); return; }
      auto install = [this, session](auto previous) {
        ReportProtocolError(previous);
        if (previous->HasKey("error")) { Resume(session); return; }
        std::string source = kNavigationLinkScript;
        source.replace(source.find("JENA_ENABLED"), 12, linksInNewTabs ? "true" : "false");
        auto params = CefDictionaryValue::Create(); params->SetString("source", source);
        params->SetString("worldName", "jena.link-policy"); params->SetBool("runImmediately", true);
        Command("Page.addScriptToEvaluateOnNewDocument", params, session, [this, session](auto result) {
          ReportProtocolError(result);
          if (!result->HasKey("error")) scripts_[session] = result->GetDictionary("result")->GetString("identifier");
          Resume(session);
        });
      };
      auto found = scripts_.find(session);
      if (found == scripts_.end()) install(CefDictionaryValue::Create());
      else { auto params = CefDictionaryValue::Create(); params->SetString("identifier", found->second);
        Command("Page.removeScriptToEvaluateOnNewDocument", params, session, install); }
    });
  }
  void Resume(const std::string &session) {
    if (session.empty() || !sessions_.contains(session)) return;
    Command("Runtime.runIfWaitingForDebugger", CefDictionaryValue::Create(), session, [](auto) {});
  }
  bool OnDevToolsMessage(CefRefPtr<CefBrowser>, const void *message, size_t size) override {
    auto value = CefParseJSON(std::string(static_cast<const char *>(message), size), JSON_PARSER_RFC);
    if (!value || value->GetType() != VTYPE_DICTIONARY) return true;
    auto event = value->GetDictionary();
    if (event->HasKey("id")) {
      auto it = replies_.find(event->GetInt("id"));
      if (it != replies_.end()) { auto reply = std::move(it->second); replies_.erase(it); reply(event); }
    } else if (event->GetString("method") == "Target.attachedToTarget") {
      auto session = event->GetDictionary("params")->GetString("sessionId").ToString();
      sessions_.insert(session); InstallPolicy(session);
    } else if (event->GetString("method") == "Target.detachedFromTarget") {
      auto session = event->GetDictionary("params")->GetString("sessionId").ToString();
      sessions_.erase(session); scripts_.erase(session);
    }
    return true;
  }
  NSString *__strong title_;
  int64_t id_;
  NSView *__strong host_;
  CefRefPtr<CefBrowser> browser_;
  CefRefPtr<CefRegistration> observer_;
  bool closeRequested_ = false;
  int commandID_ = 0;
  std::map<int, Reply> replies_;
  std::map<std::string, std::string> scripts_;
  std::set<std::string> sessions_;
  IMPLEMENT_REFCOUNTING(PageClient);
};
void ContinueQuit() {
  if (!quitting) return;
  if (pages.empty()) MaybeQuit();
  else pages.begin()->second->Action(4);
}
class EngineApp final : public CefApp, public CefBrowserProcessHandler {
 public:
  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }
  void OnContextInitialized() override { [ui engineReady]; }
  void OnBeforeCommandLineProcessing(const CefString &processType, CefRefPtr<CefCommandLine> commandLine) override {
    // The engine exposes FedCM but this app has no account-chooser UI for it, so
    // federated sign-in buttons fail silently. Without it sites use their popup flow.
    if (!processType.empty()) return;
    auto disabled = commandLine->GetSwitchValue("disable-features").ToString();
    commandLine->AppendSwitchWithValue("disable-features", disabled.empty() ? "FedCm" : disabled + ",FedCm");
  }
 private:
  IMPLEMENT_REFCOUNTING(EngineApp);
};
}

int64_t JWCreatePage(const char *url, BOOL foreground) {
  CEF_REQUIRE_UI_THREAD();
  if (quitting || privacyBusy || !WebURL(url)) return 0;
  int64_t id = ++nextPage;
  NSView *host = [ui hostForPage:id foreground:foreground];
  CefWindowInfo window;
  window.SetAsChild((__bridge CefWindowHandle)host, CefRect(0, 0, host.bounds.size.width, host.bounds.size.height));
  window.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
  auto client = new PageClient(id, host); pages[id] = client;
  CefBrowserSettings settings;
  if (!CefBrowserHost::CreateBrowser(window, client, url, settings, nullptr, nullptr)) {
    [ui page:id failed:@"페이지를 만들지 못했습니다."]; RemovePage(id); return 0;
  }
  return id;
}
void JWNavigate(int64_t page, const char *url) { auto it = pages.find(page); if (it != pages.end()) it->second->Navigate(url); }
void JWPageAction(int64_t page, int action) { auto it = pages.find(page); if (it != pages.end()) it->second->Action(action); }
void JWSetLinksInNewTabs(BOOL enabled) {
  linksInNewTabs = enabled;
  auto snapshot = pages; for (auto &[id, page] : snapshot) page->RefreshPolicy();
}
int JWSiteSetting(const char *originValue, const char *kindValue, int decision) {
  CEF_REQUIRE_UI_THREAD();
  if (quitting || privacyBusy || decision < -1 || decision > 2) return -1;
  NSString *origin = [NSString stringWithUTF8String:originValue];
  NSURLComponents *url = [NSURLComponents componentsWithString:origin];
  if ((![@"http" isEqual:url.scheme] && ![@"https" isEqual:url.scheme]) || !url.host.length ||
      url.user || url.password || url.query || url.fragment || url.path.length) return -1;
  NSDictionary *types = @{@"camera":@(CEF_CONTENT_SETTING_TYPE_MEDIASTREAM_CAMERA),
    @"microphone":@(CEF_CONTENT_SETTING_TYPE_MEDIASTREAM_MIC), @"geolocation":@(CEF_CONTENT_SETTING_TYPE_GEOLOCATION),
    @"notifications":@(CEF_CONTENT_SETTING_TYPE_NOTIFICATIONS), @"cookies":@(CEF_CONTENT_SETTING_TYPE_COOKIES), @"popups":@(CEF_CONTENT_SETTING_TYPE_POPUPS)};
  NSNumber *type = types[[NSString stringWithUTF8String:kindValue]];
  if (!type) return -1;
  auto context = CefRequestContext::GetGlobalContext();
  if (!context) return -1;
  auto contentType = static_cast<cef_content_setting_types_t>(type.intValue);
  if (decision >= 0) {
    auto value = decision == 0 ? CEF_CONTENT_SETTING_VALUE_DEFAULT :
        (decision == 1 ? CEF_CONTENT_SETTING_VALUE_ALLOW : CEF_CONTENT_SETTING_VALUE_BLOCK);
    context->SetContentSetting(originValue, originValue, contentType, value);
    if (contentType == CEF_CONTENT_SETTING_TYPE_GEOLOCATION) {
      auto options = CefValue::Create();
      if (decision == 0) options->SetNull();
      else {
        auto detail = CefDictionaryValue::Create();
        detail->SetInt("approximate", decision == 1 ? 1 : 2); detail->SetInt("precise", decision == 1 ? 1 : 2);
        options->SetDictionary(detail);
      }
      context->SetWebsiteSetting(originValue, originValue, CEF_CONTENT_SETTING_TYPE_GEOLOCATION_WITH_OPTIONS, options);
    }
  }
  return context->GetContentSetting(originValue, originValue, contentType);
}
void JWRequestQuit(void) {
  if (![ui canTerminate]) { [ui terminationCancelled]; return; }
  quitting = true;
  ContinueQuit();
}
void JWClearWebData(const char *originValue, const char *domainValue, BOOL cache, JWPrivacyCompletion completion) {
  CEF_REQUIRE_UI_THREAD();
  if (privacyBusy || quitting || pages.empty()) { completion(NO, @"웹 엔진이 다른 작업을 처리 중입니다."); return; }
  for (auto &[id, page] : pages) {
    if (!page->IsIdleBlank()) { completion(NO, @"열린 웹탭을 먼저 닫아 빈 탭만 남긴 뒤 다시 실행해주세요. 삭제는 시작하지 않았습니다."); return; }
  }
  NSString *origin = [NSString stringWithUTF8String:originValue];
  NSString *domain = [NSString stringWithUTF8String:domainValue];
  if (origin.length) {
    NSURLComponents *url = [NSURLComponents componentsWithString:origin];
    NSString *canonical = [NSString stringWithFormat:@"%@://%@%@", url.scheme.lowercaseString, url.host.lowercaseString, url.port ? [@":" stringByAppendingString:url.port.stringValue] : @""];
    if ((![@"http" isEqual:url.scheme] && ![@"https" isEqual:url.scheme]) || !domain.length ||
        ![url.host.lowercaseString isEqual:domain] || ![canonical isEqual:origin] ||
        url.user || url.password || url.query || url.fragment || url.path.length) {
      completion(NO, @"사이트 삭제 범위가 올바르지 않습니다."); return;
    }
  } else if (!cache || domain.length) { completion(NO, @"삭제 대상을 선택해주세요."); return; }
  privacyBusy = true;
  pages.begin()->second->DeleteWebData(origin, domain, cache, completion);
}
int JWRun(int argc, char **argv, const char *profile, id<JWBrowserDelegate> delegate) {
  CefScopedLibraryLoader loader;
  if (!loader.LoadInMain()) return 10;
  @autoreleasepool {
    [JenaApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    ui = delegate;
    CefSettings settings; settings.no_sandbox = false; settings.remote_debugging_port = 0;
    CefString(&settings.root_cache_path) = profile;
    CefString(&settings.cache_path) = std::string(profile) + "/default";
    CefString(&settings.log_file) = std::string(profile) + "/cef.log";
    settings.log_severity = LOGSEVERITY_ERROR;
    auto app = CefRefPtr<EngineApp>(new EngineApp);
    if (!CefInitialize(CefMainArgs(argc, argv), settings, app, nullptr)) { ui = nil; return CefGetExitCode(); }
    CefRunMessageLoop(); app = nullptr; CefShutdown(); ui = nil;
  }
  return 0;
}
