import AppKit

@main
struct JenaWebMain {
    @MainActor
    static func main() {
        do {
            let paths = try AppPaths.prepare()
            let app = try AppComposition(paths: paths)
            let code = withExtendedLifetime(app) { app.runtime.run(profile: paths.profile) }
            if code != 0 {
                let alert = NSAlert(); alert.messageText = "웹 엔진을 시작하지 못했습니다."
                alert.informativeText = "앱 구성과 설치 경로를 확인해주세요. 오류 코드: \(code)"
                alert.runModal()
            }
        } catch {
            let alert = NSAlert(); alert.messageText = "Jena Web을 열 수 없습니다."
            alert.informativeText = error.localizedDescription; alert.runModal()
        }
    }
}
