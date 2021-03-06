import Either
import Html
import HtmlPrettyPrint
import HttpPipeline
@testable import PointFree
import PointFreeTestSupport
import Prelude
import Optics
import SnapshotTesting
import XCTest

class AuthTests: TestCase {

  func testRegister() {
    let gitHubUserEnvelope = GitHub.UserEnvelope.mock
      |> \.accessToken .~ .init(accessToken: "1234-deadbeef")
      |> \.gitHubUser.id .~ 1234567890
      |> \.gitHubUser.name .~ "Blobby McBlob"

    update(
      &Current,
      (\Environment.database) .~ .live,
      \.gitHub.fetchUser .~ const(pure(gitHubUserEnvelope.gitHubUser)),
      \.gitHub.fetchAuthToken .~ const(pure(pure(gitHubUserEnvelope.accessToken)))
    )

    let result = connection(
      from: request(to: .gitHubCallback(code: "deabeef", redirect: "/"), session: .loggedOut)
      )
      |> siteMiddleware
      |> Prelude.perform
    assertSnapshot(matching: result)

    let registeredUser = Current.database
      .fetchUserByGitHub(gitHubUserEnvelope.gitHubUser.id)
      .run
      .perform()
      .right!!

    XCTAssertEqual(gitHubUserEnvelope.accessToken.accessToken, registeredUser.gitHubAccessToken)
    XCTAssertEqual(gitHubUserEnvelope.gitHubUser.id, registeredUser.gitHubUserId)
    XCTAssertEqual(gitHubUserEnvelope.gitHubUser.name, registeredUser.name)
    XCTAssertEqual(1, registeredUser.episodeCreditCount)
  }

  func testAuth() {
    let auth = request(to: .gitHubCallback(code: "deadbeef", redirect: nil))
    let conn = connection(from: auth)

    assertSnapshot(of: .ioConn, matching: conn |> siteMiddleware)
  }

  func testAuth_WithFetchAuthTokenFailure() {
    update(&Current, \.gitHub.fetchAuthToken .~ (unit |> throwE >>> const))

    let auth = request(to: .gitHubCallback(code: "deadbeef", redirect: nil))
    let conn = connection(from: auth)

    assertSnapshot(of: .ioConn, matching: conn |> siteMiddleware)
  }

  func testAuth_WithFetchAuthTokenBadVerificationCode() {
    update(
      &Current,
      \.gitHub.fetchAuthToken
        .~ const(pure(.left(.init(description: "", error: .badVerificationCode, errorUri: ""))))
    )

    let auth = request(to: .gitHubCallback(code: "deadbeef", redirect: nil))
    let conn = connection(from: auth)

    assertSnapshot(of: .ioConn, matching: conn |> siteMiddleware)
  }

  func testAuth_WithFetchAuthTokenBadVerificationCodeRedirect() {
    update(
      &Current,
      \.gitHub.fetchAuthToken
        .~ const(pure(.left(.init(description: "", error: .badVerificationCode, errorUri: ""))))
    )

    let auth = request(to: .gitHubCallback(code: "deadbeef", redirect: url(to: .episode(.right(42)))))
    let conn = connection(from: auth)

    assertSnapshot(of: .ioConn, matching: conn |> siteMiddleware)
  }

  func testAuth_WithFetchUserFailure() {
    update(&Current, \.gitHub.fetchUser .~ (unit |> throwE >>> const))

    let auth = request(to: .gitHubCallback(code: "deadbeef", redirect: nil))
    let conn = connection(from: auth)

    assertSnapshot(of: .ioConn, matching: conn |> siteMiddleware)
  }

  func testLogin() {
    let login = request(to: .login(redirect: nil))
    let conn = connection(from: login)

    assertSnapshot(of: .ioConn, matching: conn |> siteMiddleware)
  }

  func testLogin_AlreadyLoggedIn() {
    update(&Current, \.database .~ .mock)

    let login = request(to: .login(redirect: nil), session: .loggedIn)
    let conn = connection(from: login)

    assertSnapshot(of: .ioConn, matching: conn |> siteMiddleware)
  }

  func testLoginWithRedirect() {
    let login = request(to: .login(redirect: url(to: .episode(.right(42)))), session: .loggedIn)
    let conn = connection(from: login)

    assertSnapshot(of: .ioConn, matching: conn |> siteMiddleware)
  }

  func testLogout() {
    let conn = connection(from: request(to: .logout))

    assertSnapshot(of: .ioConn, matching: conn |> siteMiddleware)
  }

  func testHome_LoggedOut() {
    update(&Current, \.database .~ .mock)

    let conn = connection(from: request(to: .home, session: .loggedOut))

    assertSnapshot(of: .ioConn, matching: conn |> siteMiddleware)
  }

  func testHome_LoggedIn() {
    update(&Current, \.database .~ .mock)

    let conn = connection(from: request(to: .home, session: .loggedIn))

    assertSnapshot(of: .ioConn, matching: conn |> siteMiddleware)
  }
}
