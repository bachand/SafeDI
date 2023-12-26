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

import MacroTesting
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

import SafeDICore

#if canImport(SafeDIMacros)
@testable import SafeDIMacros

final class InstantiableMacroTests: XCTestCase {
    let testMacros: [String: Macro.Type] = [
        InstantiableVisitor.macroName: InstantiableMacro.self,
        Dependency.Source.instantiated.rawValue: InjectableMacro.self,
        Dependency.Source.received.rawValue: InjectableMacro.self,
        Dependency.Source.forwarded.rawValue: InjectableMacro.self,
    ]

    // MARK: XCTestCase

    override func invokeTest() {
        withMacroTesting(macros: testMacros) {
            super.invokeTest()
        }
    }

    // MARK: Generation tests

    func test_declaration_generatesRequiredInitializerWithoutAnyDependencies() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
            }
            """
        } expansion: {
            """
            public struct ExampleService {

                public init() {
                }
            }
            """
        }
    }

    func test_declaration_generatesRequiredInitializerWithoutAnyDependenciesAndInitializedVariable() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                var initializedVariable = "test"
            }
            """
        } expansion: {
            """
            public struct ExampleService {
                var initializedVariable = "test"

                public init() {
                }
            }
            """
        }
    }

    func test_declaration_generatesRequiredInitializerWithoutAnyDependenciesAndVariableWithAccessor() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                var initializedVariable { "test" }
            }
            """
        } expansion: {
            """
            public struct ExampleService {
                var initializedVariable { "test" }

                public init() {
                }
            }
            """
        }
    }

    func test_declaration_generatesRequiredInitializerWithDependencies() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                @Instantiated
                let receivedA: ReceivedA
            }
            """
        } expansion: {
            """
            public struct ExampleService {
                let receivedA: ReceivedA

                public init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }
            }
            """
        }
    }

    func test_declaration_generatesRequiredInitializerWithDependenciesWhenPropertyHasInitializer() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                @Instantiated
                let receivedA: ReceivedA

                let initializedProperty = 5
            }
            """
        } expansion: {
            """
            public struct ExampleService {
                let receivedA: ReceivedA

                let initializedProperty = 5

                public init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }
            }
            """
        }
    }

    func test_declaration_generatesRequiredInitializerWhenDependencyMissingFromInit() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                public init(forwardedA: ForwardedA, forwardedB: ForwardedB) {
                    self.forwardedA = forwardedA
                    self.forwardedB = forwardedB
                    receivedA = ReceivedA()
                }

                @Forwarded
                let forwardedA: ForwardedA
                @Received
                let forwardedB: ForwardedB
                @Received
                let receivedA: ReceivedA
            }
            """
        } expansion: {
            """
            public struct ExampleService {
                public init(forwardedA: ForwardedA, forwardedB: ForwardedB) {
                    self.forwardedA = forwardedA
                    self.forwardedB = forwardedB
                    receivedA = ReceivedA()
                }
                let forwardedA: ForwardedA
                let forwardedB: ForwardedB
                let receivedA: ReceivedA

                public init(forwardedA: ForwardedA, forwardedB: ForwardedB, receivedA: ReceivedA) {
                    self.forwardedA = forwardedA
                    self.forwardedB = forwardedB
                    self.receivedA = receivedA
                }
            }
            """
        }
    }

    func test_declaration_generatesRequiredInitializerWhenInstantiatorDependencyMissingFromInit() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                @Instantiated
                private let instantiatableAInstantiator: Instantiator<ReceivedA>
            }
            """
        } expansion: {
            """
            public struct ExampleService {
                private let instantiatableAInstantiator: Instantiator<ReceivedA>

                public init(instantiatableAInstantiator: Instantiator<ReceivedA>) {
                    self.instantiatableAInstantiator = instantiatableAInstantiator
                }
            }
            """
        }
    }

    // MARK: Error tests

    func test_declaration_throwsErrorWhenOnProtocol() {
        assertMacro {
            """
            @Instantiable
            public protocol ExampleService {}
            """
        } diagnostics: {
            """
            @Instantiable
            ┬────────────
            ╰─ 🛑 @Instantiable must decorate an extension on a type or a class, struct, or actor declaration
            public protocol ExampleService {}
            """
        }
    }

    func test_declaration_throwsErrorWhenOnEnum() {
        assertMacro {
            """
            @Instantiable
            public enum ExampleService {}
            """
        } diagnostics: {
            """
            @Instantiable
            ┬────────────
            ╰─ 🛑 @Instantiable must decorate an extension on a type or a class, struct, or actor declaration
            public enum ExampleService {}
            """
        }
    }

    func test_declaration_throwsErrorWhenFulfillingAdditionalTypesIsAPropertyReference() {
        assertMacro {
            """
            let fulfillingAdditionalTypes: [Any.Type] = [AnyObject.self]
            @Instantiable(fulfillingAdditionalTypes: fulfillingAdditionalTypes)
            public final class ExampleService {}
            """
        } diagnostics: {
            """
            let fulfillingAdditionalTypes: [Any.Type] = [AnyObject.self]
            @Instantiable(fulfillingAdditionalTypes: fulfillingAdditionalTypes)
            ┬──────────────────────────────────────────────────────────────────
            ╰─ 🛑 The argument `fulfillingAdditionalTypes` must be an inlined array
            public final class ExampleService {}
            """
        }
    }

    func test_declaration_throwsErrorWhenFulfillingAdditionalTypesIsAClosure() {
        assertMacro {
            """
            @Instantiable(fulfillingAdditionalTypes: { [AnyObject.self] }())
            public final class ExampleService {}
            """
        } diagnostics: {
            """
            @Instantiable(fulfillingAdditionalTypes: { [AnyObject.self] }())
            ┬───────────────────────────────────────────────────────────────
            ╰─ 🛑 The argument `fulfillingAdditionalTypes` must be an inlined array
            public final class ExampleService {}
            """
        }
    }

    func test_declaration_throwsErrorWhenMoreThanOneForwardedProperty() {
        assertMacro {
            """
            @Instantiable
            public final class UserService {
                public init(userID: String, userName: String) {
                    self.userID = userID
                    self.userName = userName
                }

                @Forwarded
                let userID: String

                @Forwarded
                let userName: String
            }
            """
        } diagnostics: {
            """
            @Instantiable
            ┬────────────
            ╰─ 🛑 An @Instantiable type must have at most one @Forwarded property
            public final class UserService {
                public init(userID: String, userName: String) {
                    self.userID = userID
                    self.userName = userName
                }

                @Forwarded
                let userID: String

                @Forwarded
                let userName: String
            }
            """
        }
    }

    func test_extension_throwsErrorWhenFulfillingAdditionalTypesIsAPropertyReference() {
        assertMacro {
            """
            let fulfillingAdditionalTypes: [Any.Type] = [AnyObject.self]
            @Instantiable(fulfillingAdditionalTypes: fulfillingAdditionalTypes)
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            let fulfillingAdditionalTypes: [Any.Type] = [AnyObject.self]
            @Instantiable(fulfillingAdditionalTypes: fulfillingAdditionalTypes)
            ┬──────────────────────────────────────────────────────────────────
            ╰─ 🛑 The argument `fulfillingAdditionalTypes` must be an inlined array
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_extension_throwsErrorWhenFulfillingAdditionalTypesIsAClosure() {
        assertMacro {
            """
            @Instantiable(fulfillingAdditionalTypes: { [AnyObject.self] }())
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @Instantiable(fulfillingAdditionalTypes: { [AnyObject.self] }())
            ┬───────────────────────────────────────────────────────────────
            ╰─ 🛑 The argument `fulfillingAdditionalTypes` must be an inlined array
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_extension_throwsErrorWhenMoreThanOneInstantiateMethod() {
        assertMacro {
            """
            @Instantiable
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
                public static func instantiate(user: User) -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @Instantiable
            ┬────────────
            ╰─ 🛑 @Instantiable-decorated extension must have a single `instantiate()` method
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
                public static func instantiate(user: User) -> ExampleService { fatalError() }
            }
            """
        }
    }

    // MARK: FixIt tests

    func test_declaration_fixit_addsFixitWhenMultipleInjectableMacrosOnTopOfSingleProperty() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                public init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }

                @Received
                @Instantiated
                let receivedA: ReceivedA
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                public init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }

                @Received
                ╰─ 🛑 Dependency can have at most one of @Instantiated, @Received, or @Forwarded attached macro
                   ✏️ Remove excessive attached macros
                @Instantiated
                let receivedA: ReceivedA
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
                public init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }

                @Received
            }
            """ // Fixes expansion is incorrect – we delete the second macro but not the property.
        }
    }

    func test_declaration_fixit_addsFixitWhenInjectableParameterHasInitializer() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                public init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }

                @Instantiated
                let receivedA: ReceivedA = .init()
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                public init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }

                @Instantiated
                ╰─ 🛑 Dependency must not have hand-written initializer
                   ✏️ Remove initializer
                let receivedA: ReceivedA = .init()
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
                public init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }

                @Instantiated
                let receivedA: ReceivedA 
            }
            """
        } expansion: {
            """
            public struct ExampleService {
                public init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }
                let receivedA: ReceivedA 
            }
            """
        }
    }

    func test_declaration_fixit_addsFixitWhenInjectableTypeIsNotPublicOrOpen() {
        assertMacro {
            """
            @Instantiable
            struct ExampleService {
                public init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }

                @Instantiated
                let receivedA: ReceivedA
            }
            """
        } diagnostics: {
            """
            @Instantiable
            ╰─ 🛑 @Instantiable-decorated type must be `public` or `open`
               ✏️ Add `public` modifier
            struct ExampleService {
                public init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }

                @Instantiated
                let receivedA: ReceivedA
            }
            """
        } fixes: {
            """
            @Instantiable
            public 
            struct ExampleService {
                public init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }

                @Instantiated
                let receivedA: ReceivedA
            }
            """
        } expansion: {
            """
            public 
            struct ExampleService {
                public init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }
                let receivedA: ReceivedA
            }
            """
        }
    }

    func test_declaration_fixit_addsFixitMissingRequiredInitializerWhenPropertyIsMissingInitializer() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                @Instantiated
                let receivedA: ReceivedA

                let uninitializedProperty: Int
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                                         ╰─ 🛑 @Instantiable-decorated type with uninitialized property must have `public` or `open` initializer comprising all injected parameters
                                            ✏️ Add required initializer
                @Instantiated
                let receivedA: ReceivedA

                let uninitializedProperty: Int
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
            public init(receivedA: ReceivedA) {
            self.receivedA = receivedA
            uninitializedProperty = <#T##assign_uninitializedProperty#>
            }

                @Instantiated
                let receivedA: ReceivedA

                let uninitializedProperty: Int
            }
            """
        } expansion: {
            """
            public struct ExampleService {
            public init(receivedA: ReceivedA) {
            self.receivedA = receivedA
            uninitializedProperty = <#T##assign_uninitializedProperty#>
            }
                let receivedA: ReceivedA

                let uninitializedProperty: Int
            }
            """ // Whitespace is correct in Xcode, but not here.
        }
    }

    func test_declaration_fixit_addsFixitMissingRequiredInitializerWhenMultiplePropertiesAreMissingInitializer() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                @Instantiated
                let receivedA: ReceivedA

                var uninitializedProperty1: Int
                let uninitializedProperty2: Int, uninitializedProperty3: Int, initializedProperty = "init"
                let (uninitializedProperty4, uninitializedProperty5): (Int, Int)
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                                         ╰─ 🛑 @Instantiable-decorated type with uninitialized property must have `public` or `open` initializer comprising all injected parameters
                                            ✏️ Add required initializer
                @Instantiated
                let receivedA: ReceivedA

                var uninitializedProperty1: Int
                let uninitializedProperty2: Int, uninitializedProperty3: Int, initializedProperty = "init"
                let (uninitializedProperty4, uninitializedProperty5): (Int, Int)
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
            public init(receivedA: ReceivedA) {
            self.receivedA = receivedA
            uninitializedProperty1 = <#T##assign_uninitializedProperty1#>
            uninitializedProperty2 = <#T##assign_uninitializedProperty2#>
            uninitializedProperty3 = <#T##assign_uninitializedProperty3#>
            (uninitializedProperty4, uninitializedProperty5) = <#T##assign_(uninitializedProperty4, uninitializedProperty5)#>
            }

                @Instantiated
                let receivedA: ReceivedA

                var uninitializedProperty1: Int
                let uninitializedProperty2: Int, uninitializedProperty3: Int, initializedProperty = "init"
                let (uninitializedProperty4, uninitializedProperty5): (Int, Int)
            }
            """
        } expansion: {
            """
            public struct ExampleService {
            public init(receivedA: ReceivedA) {
            self.receivedA = receivedA
            uninitializedProperty1 = <#T##assign_uninitializedProperty1#>
            uninitializedProperty2 = <#T##assign_uninitializedProperty2#>
            uninitializedProperty3 = <#T##assign_uninitializedProperty3#>
            (uninitializedProperty4, uninitializedProperty5) = <#T##assign_(uninitializedProperty4, uninitializedProperty5)#>
            }
                let receivedA: ReceivedA

                var uninitializedProperty1: Int
                let uninitializedProperty2: Int, uninitializedProperty3: Int, initializedProperty = "init"
                let (uninitializedProperty4, uninitializedProperty5): (Int, Int)
            }
            """ // Whitespace is correct in Xcode, but not here.
        }
    }

    func test_extension_fixit_addsFixitWhenInstantiateMethodMissing() {
        assertMacro {
            """
            @Instantiable
            extension ExampleService {
            }
            """
        } diagnostics: {
            """
            @Instantiable
            extension ExampleService {
                                      ╰─ 🛑 @Instantiable-decorated extension of ExampleService must have a `public static func instantiate() -> ExampleService` method
                                         ✏️ Add `public static func instantiate() -> ExampleService` method
            }
            """
        } fixes: {
            """
            @Instantiable
            extension ExampleService {
            public static func instantiate() -> ExampleService
            {}


            public static func instantiate() -> ExampleService
            {}
            """ // This is correct in Xcode: we only write the `instantiate()` method once.
        }
    }

    func test_extension_fixit_addsFixitWhenInstantiateMethodIsNotPublic() {
        assertMacro {
            """
            @Instantiable
            extension ExampleService {
                static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @Instantiable
            extension ExampleService {
                static func instantiate() -> ExampleService { fatalError() }
                ┬───────────────────────────────────────────────────────────
                ╰─ 🛑 @Instantiable-decorated extension must have an `instantiate()` method that is both `public` and `static`
                   ✏️ Set `public static` modifiers
            }
            """
        } fixes: {
            """
            @Instantiable
            extension ExampleService {
            public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } expansion: {
            """
            extension ExampleService {
            public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_extension_fixit_addsFixitWhenInstantiateMethodIsNotStatic() {
        assertMacro {
            """
            @Instantiable
            extension ExampleService {
                public func instantiate() -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @Instantiable
            extension ExampleService {
                public func instantiate() -> ExampleService { fatalError() }
                ┬───────────────────────────────────────────────────────────
                ╰─ 🛑 @Instantiable-decorated extension must have an `instantiate()` method that is both `public` and `static`
                   ✏️ Set `public static` modifiers
            }
            """
        } fixes: {
            """
            @Instantiable
            extension ExampleService {
            public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } expansion: {
            """
            extension ExampleService {
            public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_extension_fixit_addsFixitWhenInstantiateMethodIsNotStaticOrPublic() {
        assertMacro {
            """
            @Instantiable
            extension ExampleService {
                func instantiate() -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @Instantiable
            extension ExampleService {
                func instantiate() -> ExampleService { fatalError() }
                ┬────────────────────────────────────────────────────
                ╰─ 🛑 @Instantiable-decorated extension must have an `instantiate()` method that is both `public` and `static`
                   ✏️ Set `public static` modifiers
            }
            """
        } fixes: {
            """
            @Instantiable
            extension ExampleService {
            public static 
                func instantiate() -> ExampleService { fatalError() }
            }
            """
        } expansion: {
            """
            extension ExampleService {
            public static 
                func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_extension_fixit_addsFixitWhenInstantiateMethodReturnsIncorrectType() {
        assertMacro {
            """
            @Instantiable
            extension ExampleService {
                public static func instantiate() -> OtherExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @Instantiable
            extension ExampleService {
                public static func instantiate() -> OtherExampleService { fatalError() }
                ┬───────────────────────────────────────────────────────────────────────
                ╰─ 🛑 @Instantiable-decorated extension's `instantiate()` method must return the same type as the extended type
                   ✏️ Make `instantiate()`'s return type the same as the extended type
            }
            """
        } fixes: {
            """
            @Instantiable
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } expansion: {
            """
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_extension_fixit_addsFixitWhenInstantiateMethodIsAsync() {
        assertMacro {
            """
            @Instantiable
            extension ExampleService {
                public static func instantiate() async -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @Instantiable
            extension ExampleService {
                public static func instantiate() async -> ExampleService { fatalError() }
                ┬────────────────────────────────────────────────────────────────────────
                ╰─ 🛑 @Instantiable-decorated extension's `instantiate()` method must not throw or be async
                   ✏️ Remove effect specifiers
            }
            """
        } fixes: {
            """
            @Instantiable
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } expansion: {
            """
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_extension_fixit_addsFixitWhenInstantiateMethodThrows() {
        assertMacro {
            """
            @Instantiable
            extension ExampleService {
                public static func instantiate() throws -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @Instantiable
            extension ExampleService {
                public static func instantiate() throws -> ExampleService { fatalError() }
                ┬─────────────────────────────────────────────────────────────────────────
                ╰─ 🛑 @Instantiable-decorated extension's `instantiate()` method must not throw or be async
                   ✏️ Remove effect specifiers
            }
            """
        } fixes: {
            """
            @Instantiable
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } expansion: {
            """
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_extension_fixit_addsFixitWhenInstantiateMethodIsAsyncAndThrows() {
        assertMacro {
            """
            @Instantiable
            extension ExampleService {
                public static func instantiate() async throws -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @Instantiable
            extension ExampleService {
                public static func instantiate() async throws -> ExampleService { fatalError() }
                ┬───────────────────────────────────────────────────────────────────────────────
                ╰─ 🛑 @Instantiable-decorated extension's `instantiate()` method must not throw or be async
                   ✏️ Remove effect specifiers
            }
            """
        } fixes: {
            """
            @Instantiable
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } expansion: {
            """
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_extension_fixit_addsFixitWhenInstantiateMethodHasGenericParameter() {
        assertMacro {
            """
            @Instantiable
            extension ExampleService {
                public static func instantiate<T>() -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @Instantiable
            extension ExampleService {
                public static func instantiate<T>() -> ExampleService { fatalError() }
                ┬─────────────────────────────────────────────────────────────────────
                ╰─ 🛑 @Instantiable-decorated extension's `instantiate()` method must not have a generic parameter
                   ✏️ Remove generic parameter
            }
            """
        } fixes: {
            """
            @Instantiable
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } expansion: {
            """
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_extension_fixit_addsFixitWhenInstantiateMethodHasGenericWhereClause() {
        assertMacro {
            """
            @Instantiable
            extension Array {
                public static func instantiate() -> Array where Element == String { fatalError() }
            }
            """
        } diagnostics: {
            """
            @Instantiable
            extension Array {
                public static func instantiate() -> Array where Element == String { fatalError() }
                ┬─────────────────────────────────────────────────────────────────────────────────
                ╰─ 🛑 @Instantiable-decorated extension must not have a generic `where` clause
                   ✏️ Remove generic `where` clause
            }
            """
        } fixes: {
            """
            @Instantiable
            extension Array {
                public static func instantiate() -> Array { fatalError() }
            }
            """
        } expansion: {
            """
            extension Array {
                public static func instantiate() -> Array { fatalError() }
            }
            """
        }
    }

    func test_extension_fixit_addsFixitWhenExtensionHasGenericWhereClause() {
        assertMacro {
            """
            @Instantiable
            extension Array where Element == String {
                public static func instantiate() -> Array { fatalError() }
            }
            """
        } diagnostics: {
            """
            @Instantiable
            ┬────────────
            ╰─ 🛑 @Instantiable-decorated extension must not have a generic `where` clause
               ✏️ Remove generic `where` clause
            extension Array where Element == String {
                public static func instantiate() -> Array { fatalError() }
            }
            """
        } fixes: {
            """
            @Instantiable
            extension Array {
                public static func instantiate() -> Array { fatalError() }
            }
            """
        } expansion: {
            """
            extension Array {
                public static func instantiate() -> Array { fatalError() }
            }
            """
        }
    }
}
#endif
