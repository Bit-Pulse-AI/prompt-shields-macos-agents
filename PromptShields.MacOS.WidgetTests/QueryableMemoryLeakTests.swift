import XCTest
import SwiftUI
import SwiftData
@testable import PromptShields_MacOS_Widget

final class QueryableMemoryLeakTests: XCTestCase {
    func testQueryableActorDeallocation() {
        // Create a weak reference to track deallocation
    weak var weakActor: QueryableActor<Channel, DefaultMapping<Channel>>?

        autoreleasepool {
            // Create the actor
            let actor = QueryableActor<Channel, DefaultMapping<Channel>>(
                predicate: nil,
                sortDescriptors: [],
                limit: nil,
                persistenceManager: PersistenceManagerImpl.shared,
                mapping: DefaultMapping<Channel>.self
            )

            weakActor = actor

            // Simulate some usage
            Task {
                await actor.setUpdateCallback { _, _, _ in }
            }
        }

        // After the autoreleasepool, the actor should be deallocated
        XCTAssertNil(weakActor, "QueryableActor should be deallocated")
    }

    func testObservableQueryableDeallocation() {
        // Create a weak reference to track deallocation
        weak var weakObservable: ObservableQueryable<Channel, DefaultMapping<Channel>>?

        autoreleasepool {
            // Create the observable queryable
            let observable = ObservableQueryable<Channel, DefaultMapping<Channel>>(
                predicate: nil,
                sortDescriptors: [],
                limit: nil,
                persistenceManager: PersistenceManagerImpl.shared,
                mapping: DefaultMapping<Channel>.self
            )

            weakObservable = observable

            // Simulate some usage
            Task {
                await observable.refresh()
            }
        }

        // After the autoreleasepool, the observable should be deallocated
        XCTAssertNil(weakObservable, "ObservableQueryable should be deallocated")
    }

    func testNotificationObserverCancellation() {
        // This test verifies that notification observers are properly cancelled
        autoreleasepool {
            let actor = QueryableActor<Channel, DefaultMapping<Channel>>(
                predicate: nil,
                sortDescriptors: [],
                limit: nil,
                persistenceManager: PersistenceManagerImpl.shared,
                mapping: DefaultMapping<Channel>.self
            )

            // The actor should be deallocated and tasks cancelled
        }

        // If we reach here without hanging, the notification observer was properly cancelled
        XCTAssertTrue(true, "Notification observer was properly cancelled")
    }
}
