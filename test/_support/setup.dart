import 'dart:async';
import 'package:flutter_data/flutter_data.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../mocks.dart';
import 'book.dart';
import 'familia.dart';
import 'house.dart';
import 'node.dart';
import 'person.dart';
import 'pet.dart';

// copied from https://api.flutter.dev/flutter/foundation/kIsWeb-constant.html
const _kIsWeb = identical(0, 0.0);

// keyFor alias
final keyFor = DataModel.keyFor;

late ProviderContainer container;
late GraphNotifier graph;
Function? dispose;

final logging = [];

void setUpFn() async {
  container = ProviderContainer(
    overrides: [
      httpClientProvider.overrideWith((ref) {
        return MockClient((req) async {
          // try {
          final response = ref.watch(responseProvider);
          final text = await response.callback(req);
          return http.Response(text, response.statusCode,
              headers: response.headers);
          // } on Exception catch (e) {
          //   // unwrap provider exception
          //   // ignore: only_throw_errors
          //   throw e.exception;
          // }
        });
      }),
      hiveProvider.overrideWithValue(HiveFake()),
    ],
  );

  graph = container.read(graphNotifierProvider);
  // IMPORTANT: disable namespace assertions
  // in order to test un-namespaced (key, id)
  graph.debugAssert(false);

  // Equivalent to generated in `main.data.dart`

  await container.read(graphNotifierProvider).initialize();

  DataHelpers.setInternalType<House>('houses');
  DataHelpers.setInternalType<Familia>('familia');
  DataHelpers.setInternalType<Person>('people');
  DataHelpers.setInternalType<Dog>('dogs');
  DataHelpers.setInternalType<BookAuthor>('bookAuthors');
  DataHelpers.setInternalType<Book>('books');

  final adapterGraph = <String, RemoteAdapter<DataModel>>{
    'houses': container.read(internalHousesRemoteAdapterProvider),
    'familia': container.read(internalFamiliaRemoteAdapterProvider),
    'people': container.read(internalPeopleRemoteAdapterProvider),
    'dogs': container.read(internalDogsRemoteAdapterProvider),
    'bookAuthors': container.read(internalBookAuthorsRemoteAdapterProvider),
    'books': container.read(internalBooksRemoteAdapterProvider),
  };

  internalRepositories['houses'] = await container
      .read(housesRepositoryProvider)
      .initialize(remote: false, adapters: adapterGraph);
  internalRepositories['familia'] = await container
      .read(familiaRepositoryProvider)
      .initialize(remote: true, adapters: adapterGraph);
  internalRepositories['people'] = await container
      .read(peopleRepositoryProvider)
      .initialize(remote: false, adapters: adapterGraph);
  final dogsRepository = internalRepositories['dogs'] = await container
      .read(dogsRepositoryProvider)
      .initialize(remote: false, adapters: adapterGraph);
  internalRepositories['bookAuthors'] =
      await container.read(bookAuthorsRepositoryProvider).initialize(
            remote: false,
            adapters: adapterGraph,
          );
  internalRepositories['books'] =
      await container.read(booksRepositoryProvider).initialize(
            remote: false,
            adapters: adapterGraph,
          );

  const nodesKey = _kIsWeb ? 'node1s' : 'nodes';
  DataHelpers.setInternalType<Node>(nodesKey);
  internalRepositories[nodesKey] =
      await container.read(nodesRepositoryProvider).initialize(
    remote: false,
    adapters: {
      nodesKey: container.read(internalNodesRemoteAdapterProvider),
    },
  );

  dogsRepository.logLevel = 2;
}

void tearDownFn() async {
  // Equivalent to generated in `main.data.dart`
  dispose?.call();
  container.houses.dispose();
  container.familia.dispose();
  container.people.dispose();
  container.dogs.dispose();

  container.nodes.dispose();
  container.books.dispose();
  container.bookAuthors.dispose();
  graph.dispose();

  logging.clear();
  await oneMs();
}

// utils

/// Waits 1 millisecond (tests have a throttle of Duration.zero)
Future<void> oneMs() async {
  await Future.delayed(const Duration(milliseconds: 1));
}

Function() overridePrint(dynamic Function() testFn) => () {
      final spec = ZoneSpecification(print: (_, __, ___, String msg) {
        // Add to log instead of printing to stdout
        logging.add(msg);
      });
      return Zone.current.fork(specification: spec).run(testFn);
    };

class Bloc {
  final Repository<Familia> repo;
  Bloc(this.repo);
}

final responseProvider =
    StateProvider<TestResponse>((_) => TestResponse.text(''));

class TestResponse {
  final Future<String> Function(http.Request) callback;
  final int statusCode;
  final Map<String, String> headers;

  const TestResponse(
    this.callback, {
    this.statusCode = 200,
    this.headers = const {},
  });

  factory TestResponse.text(String text) => TestResponse((_) async => text);
}

extension ProviderContainerX on ProviderContainer {
  E watch<E>(ProviderListenable<E> provider) {
    // home baked watcher
    if (provider is ProviderBase<E>) {
      return readProviderElement(provider).readSelf();
    }
    return listen<E>(provider, ((_, next) => next)).read();
  }

  Repository<House> get houses =>
      watch(housesRepositoryProvider)..remoteAdapter.internalWatch = watch;
  Repository<Familia> get familia =>
      watch(familiaRepositoryProvider)..remoteAdapter.internalWatch = watch;
  Repository<Person> get people =>
      watch(peopleRepositoryProvider)..remoteAdapter.internalWatch = watch;
  Repository<Dog> get dogs =>
      watch(dogsRepositoryProvider)..remoteAdapter.internalWatch = watch;

  Repository<Node> get nodes =>
      watch(nodesRepositoryProvider)..remoteAdapter.internalWatch = watch;
  Repository<BookAuthor> get bookAuthors =>
      watch(bookAuthorsRepositoryProvider)..remoteAdapter.internalWatch = watch;
  Repository<Book> get books =>
      watch(booksRepositoryProvider)..remoteAdapter.internalWatch = watch;
}
