#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
@protocol JWBrowserDelegate <NSObject>
- (void)engineReady;
- (NSView *)hostForPage:(int64_t)page foreground:(BOOL)foreground;
- (void)pageCreated:(int64_t)page;
- (void)pageClosed:(int64_t)page;
- (void)page:(int64_t)page titleChanged:(NSString *)title;
- (void)page:(int64_t)page addressChanged:(NSString *)address;
- (void)page:(int64_t)page loading:(BOOL)loading back:(BOOL)back forward:(BOOL)forward;
- (void)page:(int64_t)page failed:(NSString *)message;
- (void)page:(int64_t)page visitedURL:(NSString *)url title:(NSString *)title;
- (void)terminationCancelled;
- (BOOL)canTerminate;
@end
#ifdef __cplusplus
extern "C" {
#endif
int JWRun(int argc, char * _Nullable * _Nonnull argv, const char *profile, id<JWBrowserDelegate> delegate);
int64_t JWCreatePage(const char *url, BOOL foreground);
void JWNavigate(int64_t page, const char *url);
void JWPageAction(int64_t page, int action); // 0 back, 1 forward, 2 reload, 3 stop, 4 close
void JWSetLinksInNewTabs(BOOL enabled);
void JWRequestQuit(void);
// kind: camera, microphone, geolocation, notifications, cookies, popups; decision: -1 read, 0 default, 1 allow, 2 block.
int JWSiteSetting(const char *origin, const char *kind, int decision);
typedef void (^JWPrivacyCompletion)(BOOL success, NSString *message);
void JWClearWebData(const char *origin, const char *domain, BOOL cache, JWPrivacyCompletion completion);
#ifdef __cplusplus
}
#endif
NS_ASSUME_NONNULL_END
