import Either
import SnapshotTesting
import Prelude
import XCTest
@testable import PointFree
import PointFreeTestSupport
import HttpPipeline
import Optics

class InviteTests: TestCase {
  override func setUp() {
    super.setUp()
//    record = true
  }

  func testShowInvite_LoggedOut() {
    update(&Current, \.database .~ .mock)

    let showInvite = request(to: .invite(.show(Database.TeamInvite.mock.id)))
    let conn = connection(from: showInvite)

    assertSnapshot(of: .ioConn, matching: conn |> siteMiddleware)
  }

  func testShowInvite_LoggedIn_NonSubscriber() {
    let currentUser = Database.User.mock
      |> \.id .~ .init(rawValue: UUID(uuidString: "deadbeef-dead-beef-dead-beefdead0002")!)

    let invite = Database.TeamInvite.mock
      |> \.inviterUserId .~ .init(rawValue: UUID(uuidString: "deadbeef-dead-beef-dead-beefdead0001")!)

    let db = Database.mock
      |> (\Database.fetchUserById) .~ const(pure(.some(currentUser)))
      |> \.fetchTeamInvite .~ const(pure(.some(invite)))
      |> \.fetchSubscriptionById .~ const(pure(nil))

    update(&Current, \.database .~ db)

    let showInvite = request(to: .invite(.show(invite.id)), session: .loggedIn)
    let conn = connection(from: showInvite)

    assertSnapshot(of: .ioConn, matching: conn |> siteMiddleware)
  }

  func testShowInvite_LoggedIn_Subscriber() {
    let currentUser = Database.User.mock
      |> \.id .~ .init(rawValue: UUID(uuidString: "deadbeef-dead-beef-dead-beefdead0002")!)

    let invite = Database.TeamInvite.mock
      |> \.inviterUserId .~ .init(rawValue: UUID(uuidString: "deadbeef-dead-beef-dead-beefdead0001")!)

    let db = Database.mock
      |> (\Database.fetchUserById) .~ const(pure(.some(currentUser)))
      |> \.fetchTeamInvite .~ const(pure(.some(invite)))
      |> \.fetchSubscriptionById .~ const(pure(.mock))

    update(
      &Current,
      \.database .~ db,
      \.stripe.fetchSubscription .~ const(pure(.mock |> \.status .~ .active))
    )

    let showInvite = request(to: .invite(.show(invite.id)), session: .loggedIn)
    let conn = connection(from: showInvite)

    assertSnapshot(of: .ioConn, matching: conn |> siteMiddleware)
  }

  func testResendInvite_HappyPath() {
    let currentUser = Current.database.registerUser(.mock, "hello@pointfree.co")
      .run
      .perform()
      .right!!

    let teamInvite = Current.database.insertTeamInvite("blobber@pointfree.co", currentUser.id)
      .run
      .perform()
      .right!

    let resendInvite = request(to: .invite(.resend(teamInvite.id)), session: .init(flash: nil, userId: currentUser.id))
    let conn = connection(from: resendInvite)

    assertSnapshot(of: .ioConn, matching: conn |> siteMiddleware)
  }

  func testResendInvite_CurrentUserIsNotInviter() {
    let currentUser = Current.database.registerUser(
      .mock |> \.gitHubUser.id .~ 1,
      "hello@pointfree.co"
      )
      .run
      .perform()
      .right!!

    let inviterUser = Current.database.registerUser(
      .mock |> \.gitHubUser.id .~ 2,
      "inviter@pointfree.co"
      )
      .run
      .perform()
      .right!!

    let teamInvite = Current.database.insertTeamInvite("blobber@pointfree.co", inviterUser.id)
      .run
      .perform()
      .right!

    let resendInvite = request(to: .invite(.resend(teamInvite.id)), session: .init(flash: nil, userId: currentUser.id))
    let conn = connection(from: resendInvite)

    assertSnapshot(of: .ioConn, matching: conn |> siteMiddleware)
  }

  func testRevokeInvite_HappyPath() {
    let currentUser = Current.database.registerUser(.mock, "hello@pointfree.co")
      .run
      .perform()
      .right!!

    let teamInvite = Current.database.insertTeamInvite("blobber@pointfree.co", currentUser.id)
      .run
      .perform()
      .right!

    let revokeInvite = request(to: .invite(.revoke(teamInvite.id)), session: .init(flash: nil, userId: currentUser.id))
    let conn = connection(from: revokeInvite)

    assertSnapshot(of: .ioConn, matching: conn |> siteMiddleware)

    XCTAssertNil(
      Current.database.fetchTeamInvite(teamInvite.id)
        .run
        .perform()
        .right!
    )
  }

  func testRevokeInvite_CurrentUserIsNotInviter() {
    let currentUser = Current.database.registerUser(
      .mock |> \.gitHubUser.id .~ 1,
      "hello@pointfree.co"
      )
      .run
      .perform()
      .right!!

    let inviterUser = Current.database.registerUser(
      .mock |> \.gitHubUser.id .~ 2,
      "inviter@pointfree.co"
      )
      .run
      .perform()
      .right!!

    let teamInvite = Current.database.insertTeamInvite("blobber@pointfree.co", inviterUser.id)
      .run
      .perform()
      .right!

    let revokeInvite = request(to: .invite(.revoke(teamInvite.id)), session: .init(flash: nil, userId: currentUser.id))
    let conn = connection(from: revokeInvite)

    assertSnapshot(of: .ioConn, matching: conn |> siteMiddleware)

    XCTAssertNotNil(
      Current.database.fetchTeamInvite(teamInvite.id)
        .run
        .perform()
        .right!
    )
  }

  func testAcceptInvitation_HappyPath() {
    let currentUser = Current.database.registerUser(
      .mock |> \.gitHubUser.id .~ 1,
      "hello@pointfree.co"
      )
      .run
      .perform()
      .right!!

    let inviterUser = Current.database.registerUser(
      .mock |> \.gitHubUser.id .~ 2,
      "inviter@pointfree.co"
      )
      .run
      .perform()
      .right!!

    _ = Current.database.createSubscription(Stripe.Subscription.mock, inviterUser.id)
      .run
      .perform()

    let teamInvite = Current.database.insertTeamInvite("blobber@pointfree.co", inviterUser.id)
      .run
      .perform()
      .right!

    let acceptInvite = request(to: .invite(.accept(teamInvite.id)), session: .init(flash: nil, userId: currentUser.id))
    let conn = connection(from: acceptInvite)

    assertSnapshot(of: .ioConn, matching: conn |> siteMiddleware)

    // TODO: need `Parallel` to run on main queue during tests, otherwise we can make this assertion.
    //    XCTAssertNil(
    //      Current.database.fetchTeamInvite(teamInvite.id)
    //        .run
    //        .perform()
    //        .right!
    //    )

    XCTAssertNotNil(
      Current.database.fetchUserById(currentUser.id)
        .run
        .perform()
        .right!!.subscriptionId,
      "Current user now has a subscription"
    )
  }

  func testAcceptInvitation_InviterIsNotSubscriber() {
    let currentUser = Current.database.registerUser(
      .mock |> \.gitHubUser.id .~ 1,
      "hello@pointfree.co"
      )
      .run
      .perform()
      .right!!

    let inviterUser = Current.database.registerUser(
      .mock |> \.gitHubUser.id .~ 2,
      "inviter@pointfree.co"
      )
      .run
      .perform()
      .right!!

    let teamInvite = Current.database.insertTeamInvite("blobber@pointfree.co", inviterUser.id)
      .run
      .perform()
      .right!

    let acceptInvite = request(to: .invite(.accept(teamInvite.id)), session: .init(flash: nil, userId: currentUser.id))
    let conn = connection(from: acceptInvite)

    assertSnapshot(of: .ioConn, matching: conn |> siteMiddleware)

    XCTAssertNil(
      Current.database.fetchUserById(currentUser.id)
        .run
        .perform()
        .right!!.subscriptionId,
      "Current user does not have a subscription"
    )
  }

  func testAcceptInvitation_InviterHasInactiveStripeSubscription() {
    let currentUser = Current.database.registerUser(
      .mock |> \.gitHubUser.id .~ 1,
      "hello@pointfree.co"
      )
      .run
      .perform()
      .right!!

    let inviterUser = Current.database.registerUser(
      .mock |> \.gitHubUser.id .~ 2,
      "inviter@pointfree.co"
      )
      .run
      .perform()
      .right!!

    _ = Current.database.createSubscription(Stripe.Subscription.mock, inviterUser.id)
      .run
      .perform()

    let teamInvite = Current.database.insertTeamInvite("blobber@pointfree.co", inviterUser.id)
      .run
      .perform()
      .right!

    update(&Current, \.stripe.fetchSubscription .~ const(pure(.mock |> \.status .~ .canceled)))

    let acceptInvite = request(to: .invite(.accept(teamInvite.id)), session: .init(flash: nil, userId: currentUser.id))
    let conn = connection(from: acceptInvite)

    assertSnapshot(of: .ioConn, matching: conn |> siteMiddleware)

    XCTAssertNil(
      Current.database.fetchUserById(currentUser.id)
        .run
        .perform()
        .right!!.subscriptionId,
      "Current user now has a subscription"
    )
  }

  func testAcceptInvitation_InviterHasCancelingStripeSubscription() {
    let currentUser = Current.database.registerUser(
      .mock |> \.gitHubUser.id .~ 1,
      "hello@pointfree.co"
      )
      .run
      .perform()
      .right!!

    let inviterUser = Current.database.registerUser(
      .mock |> \.gitHubUser.id .~ 2,
      "inviter@pointfree.co"
      )
      .run
      .perform()
      .right!!

    _ = Current.database.createSubscription(Stripe.Subscription.canceling, inviterUser.id)
      .run
      .perform()

    let teamInvite = Current.database.insertTeamInvite("blobber@pointfree.co", inviterUser.id)
      .run
      .perform()
      .right!

    update(&Current, \.stripe.fetchSubscription .~ const(pure(.mock |> \.status .~ .canceled)))
    
    let acceptInvite = request(to: .invite(.accept(teamInvite.id)), session: .init(flash: nil, userId: currentUser.id))
    let conn = connection(from: acceptInvite)

    assertSnapshot(of: .ioConn, matching: conn |> siteMiddleware)

    XCTAssertNil(
      Current.database.fetchUserById(currentUser.id)
        .run
        .perform()
        .right!!.subscriptionId,
      "Current user now has a subscription"
    )
  }
}
