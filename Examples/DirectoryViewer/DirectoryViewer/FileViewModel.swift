import Pilot

public struct FileViewModel: ViewModel {

    public init(model: Model, context: Context) {
        self.file = model.typedModel()
        self.context = context
    }

    public var filename: String {
        return file.url.lastPathComponent
    }

    public var url: URL {
        return file.url
    }

    public func handleDoubleClick() {
        OpenFilesAction(urls: [url]).send(from: context)
    }

    // MARK: ViewModel
    
    public let context: Context

    public func secondaryActions(for event: ViewModelUserEvent) -> [SecondaryAction] {
        return [SecondaryAction.info("Foo \(filename)")]
    }

    // MARK: Private
    private let file: File
}

extension File: ViewModelConvertible {
    public func viewModelWithContext(_ context: Context) -> ViewModel {
        return FileViewModel(model: self, context: context)
    }
}
