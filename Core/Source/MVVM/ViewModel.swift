import Foundation

// swiftlint:disable type_name

// MARK: ViewModel


/// Protocol representing a view model type, acting as the business logic layer above a `Model` and providing the
/// necessary data and methods for `View` binding.
///
/// All logic that would traditionally go in a UIView lives in this class: tap handling, sending actions, analytics,
/// interaction behaviors, etc. `View`s remain as lightweight as possible so that the functionality can be
/// unit tested without the actual view.
///
/// `ViewModel`s are typically instantiated by a `ViewModelBindingProvider` automatically as part of a UX-layer
/// binding step.
///
/// Ideally, view models should be value-types, but may be reference-types if identity/state is required.
public protocol ViewModel {

    init(model: Model, context: Context)

    /// Access to the underlying `Context`.
    var context: Context { get }

    // MARK: Interactions

    /// Returns `true` if the target view model type can handle the given user event, `false` if it cannot. The default
    /// implementation returns `true` for everything.
    func canHandleUserEvent(_ event: ViewModelUserEvent) -> Bool

    /// Invoked on the view model when the view layer wants it to handle a given user event.
    func handleUserEvent(_ event: ViewModelUserEvent)

    // MARK: Actions

    /// An array of secondary actions - typically displayed as a context menu or long-press menu depending on platform.
    func secondaryActions(for event: ViewModelUserEvent) -> [SecondaryAction]
}

/// Wraps an `Action` with additional data to be rendered in a "secondary" context like context menus or long-press
/// menus.
public struct SecondaryActionInfo {
    public struct Metadata {
        public let title: String
        public let state: State
        public let enabled: Bool
        public let imageName: String?
        public let keyEquivalent: String

        /// State of the secondary action. Note that this differs from enabled, but instead represents whether the
        /// action is "checked" in a list.
        public enum State: ExpressibleByBooleanLiteral {
            case on
            case off
            case mixed

            public init(booleanLiteral value: BooleanLiteralType) {
                if value {
                    self = .on
                } else {
                    self = .off
                }
            }
        }

        // Always provide a default value, so that it is easy to create partial Metadata to overlay on top on an
        // existing item. For example, an AppActionResponder may want to pass up Metadata(state: .on) to add
        // a checkmark to an item, without knowing the exact name of the action.
        public init(
            title: String = "",
            state: Metadata.State = .off,
            enabled: Bool = true,
            imageName: String? = nil,
            keyEquivalent: String = ""
        ) {
            self.title = title
            self.state = state
            self.enabled = enabled
            self.imageName = imageName
            self.keyEquivalent = keyEquivalent
        }

        // Enforce some common conventions (for example, state is off, no keyEquivalent).
        public static func forNestedActions(
            title: String,
            enabled: Bool = true,
            imageName: String? = nil
        ) -> Metadata {
            return Metadata(title: title, state: .off, enabled: enabled, imageName: imageName)
        }
    }

    public init(metadata: Metadata, action: Action) {
        self.metadata = metadata
        self.action = action
    }

    public let metadata: Metadata
    public let action: Action
}

/// Describes a group of nested SecondaryActions.
public struct NestedActionsInfo {
    public init(metadata: SecondaryActionInfo.Metadata, actions: [SecondaryAction]) {
        self.metadata = metadata
        self.actions = actions
    }

    public let metadata: SecondaryActionInfo.Metadata
    public let actions: [SecondaryAction]
}

/// Represents a secondary action to be displayed in a list to the user (typically from right-click or long-press).
public enum SecondaryAction {
    case action(SecondaryActionInfo)
    case info(String)
    case separator
    case nested(NestedActionsInfo)
}

/// Default implementations so `ViewModel`s may opt-in to only interactions they care about.
public extension ViewModel {

    func handleUserEvent(_ event: ViewModelUserEvent) {}

    /// By default returns true for all non-keyboard and pasteboard events.
    func canHandleUserEvent(_ event: ViewModelUserEvent) -> Bool {
        switch event {
        case .click, .longPress, .secondaryClick, .select, .tap: return true
        case .keyDown, .copy: return false
        }
    }

    func secondaryActions(for event: ViewModelUserEvent) -> [SecondaryAction] {
        return []
    }
}

// MARK: Binding

/// An optional protocol that types may adopt in order to provide a `ViewModel` directly. This is the default method
/// `ViewModelBindingProvider` uses to instantiate a `ViewModel`.
public protocol ViewModelConvertible {

    /// Return a `ViewModel` representing the target type.
    func viewModelWithContext(_ context: Context) -> ViewModel
}

/// Core binding provider protocol to generate `ViewModel` instances from `Model` instances.
public protocol ViewModelBindingProvider {

    /// Returns a `ViewModel` for the given `Model` and context.
    func viewModel(for model: Model, context: Context) -> ViewModel

    /// Returns the `SelectionViewModel` for given collection of models and a context. The default implementation
    /// returns selection view model that works for a single model.
    func selectionViewModel(for models: [Model], context: Context) -> SelectionViewModel?
}

extension ViewModelBindingProvider {
    public func selectionViewModel(for models: [Model], context: Context) -> SelectionViewModel? {
        if let firstModel = models.first, models.count == 1 {
            return ViewModelSelectionShim(viewModels: [viewModel(for: firstModel, context: context)])
        }
        return nil
    }
}

/// Represents a selection of one or more view models.
public protocol SelectionViewModel {
    /// Initialize with a collection of view models.
    init(viewModels: [ViewModel])
    /// Returns `true` if the selection can handle the given user event, `false` if it cannot.
    func canHandleUserEvent(_ event: ViewModelUserEvent) -> Bool
    /// Invoked on the selection when the view layer wants it to handle a given user event.
    func handleUserEvent(_ event: ViewModelUserEvent)
    /// An array of secondary actions for the selection - typically displayed as a context menu or long-press menu
    /// depending on platform.
    func secondaryActions(for event: ViewModelUserEvent) -> [SecondaryAction]
}

/// A `ViewModelBindingProvider` which provides default behavior to check the `Model` for conformance to
/// `ViewModelConvertible`.
public struct DefaultViewModelBindingProvider: ViewModelBindingProvider {

    public init() {}

    // MARK: ViewModelBindingProvider

    public func viewModel(for model: Model, context: Context) -> ViewModel {
        guard let convertible = model as? ViewModelConvertible else {
            // Programmer error to fail to provide a binding.
            // - TODO:(wkiefer) Avoid `fatalError` for programmer binding errors - return default empty views & assert.
            fatalError(
                "Default ViewModel binding requires model to conform to `ViewModelConvertible`: \(type(of: model))")
        }
        return convertible.viewModelWithContext(context)
    }
}

/// A `ViewModelBindingProvider` that delegates to a closure to provide the appropriate `ViewModel` for the
/// supplied `Model` and `Context`. It will fallback to the `DefaultViewModelBindingProvider` implementation
/// if no `ViewModel` is returned.
public struct BlockViewModelBindingProvider: ViewModelBindingProvider {
    public init(binder: @escaping (Model, Context) -> ViewModel?) {
        self.binder = binder
    }

    public func viewModel(for model: Model, context: Context) -> ViewModel {
        return self.binder(model, context) ?? DefaultViewModelBindingProvider().viewModel(for: model, context: context)
    }

    private let binder: (Model, Context) -> ViewModel?
}

/// Simple shim that forwards methods from `SelectionViewModel` to a single `ViewModel`.
fileprivate struct ViewModelSelectionShim: SelectionViewModel {
    init(viewModels: [ViewModel]) {
        guard let vm = viewModels.first else { fatalError("Shim constructed with empty view model collection") }
        self.viewModel = vm
    }

    func canHandleUserEvent(_ event: ViewModelUserEvent) -> Bool {
        return viewModel.canHandleUserEvent(event)
    }

    func handleUserEvent(_ event: ViewModelUserEvent) {
        return viewModel.handleUserEvent(event)
    }

    func secondaryActions(for event: ViewModelUserEvent) -> [SecondaryAction] {
        return viewModel.secondaryActions(for: event)
    }

    var viewModel: ViewModel
}
