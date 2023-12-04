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

public final class DependencyTreeGenerator {

    // MARK: Initialization

    public init(
        moduleNames: [String],
        typeDescriptionToFulfillingInstantiableMap: [TypeDescription: Instantiable]
    ) {
        self.moduleNames = moduleNames
        self.typeDescriptionToFulfillingInstantiableMap = typeDescriptionToFulfillingInstantiableMap
    }

    // MARK: Public

    public func generate() async throws -> String {
        try validateReachableTypeDescriptions()
        try validateAtLeastOneRootFound()
        // showstopper TODO: Validate that all @Singleton properties are never @Constructed (or @Inherited??)

        let typeDescriptionToScopeMap = try createTypeDescriptionToScopeMapping()
        try assignSingletonsToScopes(typeDescriptionToScopeMap: typeDescriptionToScopeMap)
        try propagateUndeclaredInheritedProperties(typeDescriptionToScopeMap: typeDescriptionToScopeMap)
        let rootScopes = rootInstantiableTypes.compactMap({ typeDescriptionToScopeMap[$0] })
        _ = rootScopes

        return """
        // This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
        // Any modifications made to this file will be overwritten on subsequent builds.
        // Please refrain from editing this file directly.

        \(imports)

        // TODO: Generate scopes.
        // TODO: Generate extensions for rootInstantiableTypes so they can be instantiated with an `init()` (if they don't already have one) using the scope.

        """ // showstopper TODO: finish generating
    }

    // MARK: Private

    private let moduleNames: [String]
    private let typeDescriptionToFulfillingInstantiableMap: [TypeDescription: Instantiable]

    private var imports: String {
        moduleNames
            .map { "import \($0)" }
            .joined(separator: "\n")
    }

    /// A collection of `@Instantiable`-decorated types that do not explicitly inherit dependencies.
    /// - Note: These are not necessarily roots in the build graph, since these types may be instantiated by another `@Instantiable`.
    ///         These types may also inherit (rather than construct) a `@Singleton` dependency.
    private lazy var possibleRootInstantiableTypes: Set<TypeDescription> = Set(
        typeDescriptionToFulfillingInstantiableMap
            .values
            .filter(\.dependencies.areAllInstantiated)
            .map(\.concreteInstantiableType)
    )

    /// A collection of `@Instantiable`-decorated types that are instantiated by at least one other
    /// `@Instantiable`-decorated type or do not explicitly inherit dependencies.
    private lazy var reachableTypeDescriptions: Set<TypeDescription> = {
        var reachableTypeDescriptions = Set<TypeDescription>()

        func recordReachableTypeDescription(_ reachableTypeDescription: TypeDescription) {
            guard !reachableTypeDescriptions.contains(reachableTypeDescription) else {
                // We've visited this tree already. Ignore.
                return
            }
            guard let instantiable = typeDescriptionToFulfillingInstantiableMap[reachableTypeDescription] else {
                // We can't find an instantiable for this type.
                // This is bad, but we handle this error in `validateReachableTypeDescriptions()`.
                return
            }
            reachableTypeDescriptions.insert(reachableTypeDescription)
            let reachableChildTypeDescriptions = instantiable
                .dependencies
                .filter(\.isInstantiated)
                .map(\.property.typeDescription.asInstantiatedType)
            for reachableChildTypeDescription in reachableChildTypeDescriptions {
                recordReachableTypeDescription(reachableChildTypeDescription)
            }
        }

        for reachableTypeDescription in possibleRootInstantiableTypes {
            recordReachableTypeDescription(reachableTypeDescription)
        }

        return reachableTypeDescriptions
    }()

    /// A collection of `@Instantiable`-decorated types that are instantiated by another
    /// `@Instantiable`-decorated type that is reachable in the dependency tree.
    private lazy var childInstantiableTypes: Set<TypeDescription> = Set(
        reachableTypeDescriptions
            .compactMap { typeDescriptionToFulfillingInstantiableMap[$0] }
            .flatMap(\.dependencies)
            .filter(\.isInstantiated)
            .map(\.property.typeDescription.asInstantiatedType)
    )

    /// A collection of `@Instantiable`-decorated types that are at the roots of their respective dependency trees.
    private lazy var rootInstantiableTypes: Set<TypeDescription> = possibleRootInstantiableTypes
        .subtracting(childInstantiableTypes)

    private func createTypeDescriptionToScopeMapping() throws -> [TypeDescription: Scope] {
        // Create the mapping.
        let typeDescriptionToScopeMap: [TypeDescription: Scope] = reachableTypeDescriptions
            .reduce(into: [TypeDescription: Scope](), { partialResult, typeDescription in
                guard let instantiable = typeDescriptionToFulfillingInstantiableMap[typeDescription] else {
                    // We can't find an instantiable for this type.
                    // This is bad, but we handle this error in `validateReachableTypeDescriptions()`.
                    return
                }
                guard partialResult[instantiable.concreteInstantiableType] == nil else {
                    // We've already created a scope for this `instantiable`. Skip.
                    return
                }
                let scope = Scope(instantiable: instantiable)
                for instantiableType in instantiable.instantiableTypes {
                    partialResult[instantiableType] = scope
                }
            })

        // Populate the propertiesToInstantiate on each scope.
        for scope in typeDescriptionToScopeMap.values {
            var additionalPropertiesToInstantiate = [Scope.PropertyToInstantiate]()
            for instantiatedProperty in scope.instantiable.instantiatedProperties {
                let instantiatedType = instantiatedProperty.typeDescription.asInstantiatedType
                guard
                    let instantiable = typeDescriptionToFulfillingInstantiableMap[instantiatedType],
                    let instantiatedScope = typeDescriptionToScopeMap[instantiatedProperty.typeDescription]
                else {
                    assertionFailure("Invalid state. Could not look up info for \(instantiatedProperty.typeDescription)")
                    continue
                }
                additionalPropertiesToInstantiate.append(Scope.PropertyToInstantiate(
                    property: instantiatedProperty,
                    instantiable: instantiable,
                    scope: instantiatedScope,
                    type: instantiatedProperty.nonLazyPropertyType
                ))
            }
            for instantiatedProperty in scope.instantiable.lazyInstantiatedProperties {
                let instantiatedType = instantiatedProperty.typeDescription.asInstantiatedType
                guard
                    let instantiable = typeDescriptionToFulfillingInstantiableMap[instantiatedType],
                    let instantiatedScope = typeDescriptionToScopeMap[instantiatedType]
                else {
                    assertionFailure("Invalid state. Could not look up info for \(instantiatedProperty.typeDescription)")
                    continue
                }

                additionalPropertiesToInstantiate.append(Scope.PropertyToInstantiate(
                    property: instantiatedProperty,
                    instantiable: instantiable,
                    scope: instantiatedScope,
                    type: .lazy
                ))
            }
            scope.propertiesToInstantiate.append(contentsOf: additionalPropertiesToInstantiate)
        }
        // Note: Singletons have not been assigned to scopes yet!
        return typeDescriptionToScopeMap
    }

    private func assignSingletonsToScopes(typeDescriptionToScopeMap: [TypeDescription: Scope]) throws {
        /// A mapping of singleton properties to the scopes that require this property.
        var singletonPropertyToScopesCountMap: [Property: Int] = typeDescriptionToScopeMap
            .values
            .reduce(into: [Property: Int]()) { partialResult, scope in
                for property in scope.instantiable.singletonProperties {
                    partialResult[property, default: 0] += 1
                }
            }
        var scopeIdentifierToSingletonPropertyToScopesInTreeCount = [ObjectIdentifier: [Property: Int]]()
        func recordSingletonPropertiesOnScope(_ scope: Scope, parentScopes: [Scope]) {
            let scopes = [scope] + parentScopes // parentScopes has root scope as last.
            for singletonProperty in scope.instantiable.singletonProperties {
                for (index, scope) in scopes.enumerated() {
                    let scopesInTreeUtilizingSingletonProperty = (scopeIdentifierToSingletonPropertyToScopesInTreeCount[ObjectIdentifier(scope)]?[singletonProperty] ?? 0) + 1
                    defer {
                        scopeIdentifierToSingletonPropertyToScopesInTreeCount[ObjectIdentifier(scope), default: [Property: Int]()][singletonProperty] = scopesInTreeUtilizingSingletonProperty
                    }
                    if
                        singletonPropertyToScopesCountMap[singletonProperty] == scopesInTreeUtilizingSingletonProperty,
                        let singletonPropertyScope = typeDescriptionToScopeMap[singletonProperty.typeDescription.asInstantiatedType]
                    {
                        scope.propertiesToInstantiate.append(Scope.PropertyToInstantiate(
                            property: singletonProperty,
                            instantiable: singletonPropertyScope.instantiable,
                            scope: singletonPropertyScope,
                            type: singletonProperty.nonLazyPropertyType // Singletons can not be lazy
                        ))
                        // Remove the singleton property from our tracker so we can find orphaned singletons later.
                        singletonPropertyToScopesCountMap[singletonProperty] = nil
                        // Visit the scope we just placed.
                        recordSingletonPropertiesOnScope(singletonPropertyScope, parentScopes: Array(scopes.dropFirst(index)))
                        // We don't need to keep traversing up the tree because we found what we're looking for.
                        break
                    }
                }
            }
            for childScope in scope.propertiesToInstantiate.map(\.scope) {
                guard !parentScopes.contains(where: { $0 === childScope }) else {
                    // We've previously visited this child scope.
                    // There is a cycle in our scope tree. Do not re-enter it.
                    continue
                }
                recordSingletonPropertiesOnScope(childScope, parentScopes: scopes)
            }
        }

        let rootScopes = rootInstantiableTypes.compactMap({ typeDescriptionToScopeMap[$0] })
        for rootScope in rootScopes {
            recordSingletonPropertiesOnScope(rootScope, parentScopes: [])
        }
        if !singletonPropertyToScopesCountMap.isEmpty {
            throw DependencyTreeGeneratorError.unsatisfiableSingletons(
                Array(singletonPropertyToScopesCountMap.keys),
                roots: rootScopes.map(\.instantiable.concreteInstantiableType)
            )
        }
    }

    private func propagateUndeclaredInheritedProperties(typeDescriptionToScopeMap: [TypeDescription: Scope]) throws {
        var unfulfillableProperties = [DependencyTreeGeneratorError.UnfulfillableProperty]()
        func propagateUndeclaredInheritedProperties(on scope: Scope, parentScopes: [Scope]) {
            func indexOfParentScopeThatVendsProperty(_ property: Property) -> Int? {
                parentScopes
                    .firstIndex(where: { parentScope in
                        parentScope
                            .instantiatedProperties
                            .contains(property)
                        || parentScope
                            .instantiable
                            .forwardedProperties
                            .contains(property)
                        || parentScope
                            .allInheritedProperties
                            .contains(property)
                    })
            }
            for inheritedProperty in scope.inheritedProperties {
                if let indexOfPropertyVendingParentScope = indexOfParentScopeThatVendsProperty(inheritedProperty) {
                    if indexOfPropertyVendingParentScope > 0 {
                        // A parent scope more than one parent up the tree vends this property.
                        // Make sure intermediate parent scopes vend this property for us.
                        let pathToParentThatVendsProperty = parentScopes[0..<indexOfPropertyVendingParentScope]
                        for parentScope in pathToParentThatVendsProperty {
                            parentScope.undeclaredInheritedProperties.insert(inheritedProperty)
                        }
                    }
                } else {
                    unfulfillableProperties.append(.init(
                        property: inheritedProperty,
                        instantiable: scope.instantiable,
                        parentStack: parentScopes.map(\.instantiable))
                    )
                }
            }

            for childScope in scope.propertiesToInstantiate.map(\.scope) {
                guard !parentScopes.contains(where: { $0 === childScope }) else {
                    // We've previously visited this child scope.
                    // There is a cycle in our scope tree. Do not re-enter it.
                    continue
                }
                propagateUndeclaredInheritedProperties(
                    on: childScope,
                    // parentScopes has root scope as last.
                    parentScopes: [scope] + parentScopes)
            }
        }

        for rootScope in rootInstantiableTypes.compactMap({ typeDescriptionToScopeMap[$0] }) {
            propagateUndeclaredInheritedProperties(on: rootScope, parentScopes: [])
        }

        if !unfulfillableProperties.isEmpty {
            throw DependencyTreeGeneratorError.unfulfillableProperties(unfulfillableProperties)
        }
    }

    private func validateReachableTypeDescriptions() throws {
        for reachableTypeDescription in reachableTypeDescriptions {
            if typeDescriptionToFulfillingInstantiableMap[reachableTypeDescription] == nil {
                throw DependencyTreeGeneratorError.noInstantiableFound(reachableTypeDescription)
            }
        }
    }

    private func validateAtLeastOneRootFound() throws {
        if rootInstantiableTypes.isEmpty {
            throw DependencyTreeGeneratorError.noRootInstantiableFound
        }
    }
}

extension Dependency {
    fileprivate var isInstantiated: Bool {
        switch source {
        case .instantiated, .lazyInstantiated, .singleton:
            return true
        case .forwarded, .inherited:
            return false
        }
    }
}

extension Property {
    fileprivate var nonLazyPropertyType: Scope.PropertyToInstantiate.PropertyType {
        switch typeDescription {
        case let .simple(name, _):
            if name == Dependency.lazyInstantiatorType {
                return .instantiator
            } else if name == Dependency.lazyForwardingInstantiatorType {
                return .forwardingInstantiator
            } else {
                return .constant
            }
        case .any,
                .array,
                .attributed,
                .closure,
                .composition,
                .dictionary,
                .implicitlyUnwrappedOptional,
                .metatype,
                .nested,
                .optional,
                .some,
                .tuple,
                .unknown:
            return .constant
        }
    }

}

extension Array where Element == Dependency {
    fileprivate var areAllInstantiated: Bool {
        first(where: { !$0.isInstantiated }) == nil
    }
}

extension TypeDescription {
    fileprivate var asInstantiatedType: TypeDescription {
        switch self {
        case let .simple(name, generics):
            if name == Dependency.lazyInstantiatorType, let builtType = generics.first {
                // This is a type that is lazily instantiated.
                // The first generic is the built type.
                return builtType
            } else if name == Dependency.lazyForwardingInstantiatorType, let builtType = generics.last {
                // This is a type that is lazily instantiated with forwarded arguments.
                // The last generic is the built type.
                return builtType
            } else {
                return self
            }
        case .any,
                .array,
                .attributed,
                .closure,
                .composition,
                .dictionary,
                .implicitlyUnwrappedOptional,
                .metatype,
                .nested,
                .optional,
                .some,
                .tuple,
                .unknown:
            return self
        }
    }
}
