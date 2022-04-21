part of flutter_data;

mixin _RemoteAdapterWatch<T extends DataModel<T>> on _RemoteAdapter<T> {
  @protected
  @visibleForTesting
  DataStateNotifier<List<T>?> watchAllNotifier({
    bool? remote,
    Map<String, dynamic>? params,
    Map<String, String>? headers,
    bool? syncLocal,
    String? finder,
    DataRequestLabel? label,
  }) {
    _assertInit();
    remote ??= _remote;
    syncLocal ??= false;

    final _maybeFinder = _internalHolder?.finders[finder]?.call(this);
    final _finder = _maybeFinder is DataFinderAll<T> ? _maybeFinder : findAll;
    label ??= DataRequestLabel('findAll', type: internalType);

    // closure to get latest models
    List<T>? _getUpdatedModels() {
      return localAdapter
          .findAll()
          ?.map((m) => m._initialize(adapters))
          .toList();
    }

    final _notifier = DataStateNotifier<List<T>?>(
      data: DataState(_getUpdatedModels(), isLoading: remote!),
    );

    _notifier.reloadFn = () async {
      if (!_notifier.mounted) return;

      if (remote!) {
        _notifier.updateWith(isLoading: true);
      }

      try {
        await _finder(
          remote: remote,
          params: params,
          headers: headers,
          syncLocal: syncLocal,
          label: label,
          onError: (e, _) => throw e,
        );
        if (remote) {
          // trigger doneLoading to ensure state is updated with isLoading=false
          graph._notify([label.toString()],
              type: DataGraphEventType.doneLoading);
        }
      } on DataException catch (e) {
        if (_notifier.mounted) {
          _notifier.updateWith(isLoading: false, exception: e);
        } else {
          rethrow;
        }
      }
    };

    // kick off
    _notifier.reload();

    final _dispose = graph.addListener((event) {
      if (!_notifier.mounted) return;

      // handle done loading
      if (_notifier.data.isLoading &&
          event.keys.last == label.toString() &&
          event.type == DataGraphEventType.doneLoading) {
        final models = _getUpdatedModels();
        _notifier.updateWith(model: models, isLoading: false, exception: null);
      }

      if (_notifier.data.isLoading == false &&
          event.type.isNode &&
          event.keys.first.startsWith(internalType)) {
        final models = _getUpdatedModels();
        _notifier.updateWith(model: models);
      }
    });

    _notifier.onDispose = _dispose;
    return _notifier;
  }

  DataState<List<T>?> watchAll({
    bool? remote,
    Map<String, dynamic>? params,
    Map<String, String>? headers,
    bool? syncLocal,
    String? finder,
    DataRequestLabel? label,
  }) {
    if (internalWatch == null || _internalHolder?.allProvider == null) {
      throw UnsupportedError(_watchAllError);
    }
    final provider = _internalHolder!.allProvider!(
      remote: remote,
      params: params,
      headers: headers,
      syncLocal: syncLocal,
      label: label,
    );
    return internalWatch!(provider);
  }

  String get _watchAllError =>
      'Should only be used via `ref.$type.watchAll`. Alternatively use `watch${type.capitalize()}()`.';

  // one

  @protected
  @visibleForTesting
  DataStateNotifier<T?> watchOneNotifier(
    Object model, {
    bool? remote,
    Map<String, dynamic>? params,
    Map<String, String>? headers,
    AlsoWatch<T>? alsoWatch,
    String? finder,
    DataRequestLabel? label,
  }) {
    _assertInit();

    remote ??= _remote;
    final _maybeFinder = _internalHolder?.finders[finder]?.call(this);
    final _finder = _maybeFinder is DataFinderOne<T> ? _maybeFinder : findOne;
    label ??= DataRequestLabel('findOne', type: internalType);

    final id = _resolveId(model);

    var _alsoWatchPairs = <List<String>>{};

    // lazy key access
    String? key() {
      return graph.getKeyForId(internalType, id,
          keyIfAbsent: (model is T ? model._key : null));
    }

    // closure to get latest model and watchable relationship pairs
    T? _getUpdatedModel({DataStateNotifier<T?>? withNotifier}) {
      final model = localAdapter.findOne(key())?._initialize(adapters);
      if (model != null) {
        model._initializeRelationships();
        _alsoWatchPairs = {
          ...?alsoWatch?.call(model).filterNulls.map((r) {
            return r.keys.map((key) => [r._ownerKey, key]);
          }).expand((_) => _)
        };
        if (withNotifier != null) {
          model._updateNotifier(withNotifier);
        }
      }
      return model;
    }

    final _notifier = DataStateNotifier<T?>(
      data: DataState(_getUpdatedModel(), isLoading: remote!),
    );

    _notifier.reloadFn = () async {
      if (!_notifier.mounted || id == null) return;

      if (remote!) {
        _notifier.updateWith(isLoading: true);
      }

      try {
        final model = await _finder(
          id,
          remote: remote,
          params: params,
          headers: headers,
          onError: (e, _) => throw e,
        );
        // trigger doneLoading to ensure state is updated with isLoading=false
        final _key = model?._key!;
        if (remote && _key != null) {
          graph._notify([_key, label.toString()],
              type: DataGraphEventType.doneLoading);
        }
      } on DataException catch (e) {
        if (_notifier.mounted) {
          _notifier.updateWith(isLoading: false, exception: e);
        } else {
          rethrow;
        }
      }
    };

    // trigger local + async loading
    _notifier.reload();

    // local buffer useful to reduce amount of notifier updates
    var _model = _notifier.data.model;

    // start listening to graph for further changes
    final _dispose = graph.addListener((event) {
      if (!_notifier.mounted) return;

      final _key = key();

      // get the latest updated model with watchable relationships
      // (_alsoWatchPairs) in order to determine whether there is
      // something that will cause a notification (with the introduction
      // of `andEach` even seemingly unrelated models could trigger)
      _model = _getUpdatedModel(withNotifier: _notifier);

      if (event.keys.contains(_key)) {
        // handle done loading
        if (_notifier.data.isLoading &&
            event.keys.last == label.toString() &&
            event.type == DataGraphEventType.doneLoading) {
          _notifier.updateWith(
              model: _model, isLoading: false, exception: null);
        }

        // add/update
        if (event.type == DataGraphEventType.addNode ||
            event.type == DataGraphEventType.updateNode) {
          if (_notifier.data.isLoading == false) {
            _notifier.updateWith(model: _model);
          }
        }

        // remove
        if (event.type == DataGraphEventType.removeNode) {
          _notifier.updateWith(model: null);
        }

        // temporarily restore removed pair so that watchedRelationshipUpdate
        // has a chance to apply the update
        if (event.type == DataGraphEventType.removeEdge) {
          _alsoWatchPairs.add(event.keys);
        }
      }

      // updates on watched relationships condition
      final watchedRelationshipUpdate = event.type.isEdge &&
          _alsoWatchPairs
              .where((pair) =>
                  pair.sorted().toString() == event.keys.sorted().toString())
              .isNotEmpty;

      // updates on watched models (of relationships) condition
      final watchedModelUpdate = event.type.isNode &&
          _alsoWatchPairs
              .where((pair) => pair.contains(event.keys.first))
              .isNotEmpty;

      // if model is loaded and any condition passes, notify update
      if (_notifier.data.isLoading == false &&
          (watchedRelationshipUpdate || watchedModelUpdate)) {
        _notifier.updateWith(model: _model);
      }
    });

    _notifier.onDispose = () {
      _dispose();
    };
    return _notifier;
  }

  DataState<T?> watchOne(
    Object model, {
    bool? remote,
    Map<String, dynamic>? params,
    Map<String, String>? headers,
    AlsoWatch<T>? alsoWatch,
    String? finder,
    DataRequestLabel? label,
  }) {
    if (internalWatch == null || _internalHolder?.oneProvider == null) {
      throw UnsupportedError(_watchOneError);
    }
    final provider = _internalHolder!.oneProvider!(
      model,
      remote: remote,
      params: params,
      headers: headers,
      alsoWatch: alsoWatch,
      label: label,
    );
    return internalWatch!(provider);
  }

  String get _watchOneError =>
      'Should only be used via `ref.$type.watchOne`. Alternatively use `watch${type.singularize().capitalize()}()`.';
}

typedef AlsoWatch<T extends DataModel<T>> = Iterable<Relationship?> Function(T);
