// Distributed under the MIT License
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation

/// Marks a SafeDI dependency that is instantiated on first access. Thread-safe.
@propertyWrapper public final class LazyInstantiated<InstantiableType> {

    // MARK: Initialization

    public init(synchronization: SynchronizationBehavior = .main, _ builder: Instantiator<InstantiableType>) {
        self.instantiator = builder
        self.synchronization = synchronization
    }

    // MARK: Public

    public var wrappedValue: InstantiableType {
        synchronization.sync {
            if let instantiated = self._unsafeInstantiated {
                return instantiated
            } else {
                let instantiated = self.instantiator.instantiate()
                self._unsafeInstantiated = instantiated
                return instantiated
            }
        }
    }

    // MARK: Private

    private let instantiator: Instantiator<InstantiableType>
    private let synchronization: SynchronizationBehavior
    private var _unsafeInstantiated: InstantiableType?

    // MARK: - SynchronizationBehavior

    public enum SynchronizationBehavior {
        /// Synchronizes access on the main queue.
        /// Use this if your parent is a @MainActor.
        case main
        /// Synchronizes access behind a lock.
        case lock(lock: NSLock = NSLock())

        func sync<T>(block: () -> T) -> T {
            switch self {
            case .main:
                if Thread.isMainThread {
                    return block()
                } else {
                    return DispatchQueue.main.sync(execute: block)
                }
            case let .lock(lock):
                lock.lock()
                defer { lock.unlock() }
                return block()
            }
        }
    }
}