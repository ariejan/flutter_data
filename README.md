<p align="center" style="margin-bottom: 0px;">
  <img src="https://avatars2.githubusercontent.com/u/61839689?s=200&v=4" width="85px">
</p>

<h1 align="center" style="margin-top: 0px; font-size: 4em;">Flutter Data</h1>

[![tests](https://img.shields.io/github/workflow/status/flutterdata/flutter_data/test/master?label=tests&labelColor=333940&logo=github)](https://github.com/flutterdata/flutter_data/actions) [![pub.dev](https://img.shields.io/pub/v/flutter_data?label=pub.dev&labelColor=333940&logo=dart)](https://pub.dev/packages/flutter_data) [![license](https://img.shields.io/github/license/flutterdata/flutter_data?color=%23007A88&labelColor=333940&logo=mit)](https://github.com/flutterdata/flutter_data/blob/master/LICENSE)

<!-- keep leading space to prevent re-generate toc -->
-  [🌎 Philosophy](#-philosophy)
- [🔧 Installing and configuring](#-installing-and-configuring)
- [👩🏾‍💻 API](#-api)
  - [Repository API](#repository-api)
  - [DataSupport and Relationships API](#datasupport-and-relationships-api)
- [👩‍🍳 Cookbook/FAQ](#-cookbookfaq)
- [📲 Apps using Flutter Data](#-apps-using-flutter-data)

### Working on a Flutter app that talks to an API server?

You want to retrieve data, serialize it, store it for offline use and hook it up with your state management solution – all that for 20 interconnected entities in your app.

Trying to make this work with ad-hoc HTTP calls, custom loading/error states, caching,  json_serializable, Chopper or Firebase, Provider, authentication (not to mention sync'ing with local storage, Hive or SQLite)... can be painful 😫.

**What if you could get it all working smoothly with minimal effort?**

### 🗒 Mini TO-DO list example

Let's display [JSON Placeholder](https://jsonplaceholder.typicode.com/) _user 1_'s list of TO-DOs:

```dart
FutureBuilder<List<Todo>>(
  future: context.read<Repository<Todo>>().findAll(params: {'userId': '1'});
  builder: (context, snapshot) {
    return ListView.builder(
      itemBuilder: (context, i) {
        final todo = snapshot.data[i];
        // Text or other more complex widget
        return Text('TO-DO: ${todo.title}'),
      },
    );
  }
}
```

Result:

![](docs/10-user.png)

(This is a snapshot of the **final version of the app**: https://github.com/flutterdata/flutter_data_todos !)

We just:

 - Got hold of a repository for `Todo` via Provider
 - Fetched a TO-DO list for a user with id=1 (URL: `https://jsonplaceholder.typicode.com/todos?userId=1`)
 - Deserialized JSON data into a list of `Todo` models
 - Displayed the list in a `FutureBuilder`

How was all that possible?

1. We annotated a `Todo` with `@DataRepository`
2. We made our model `extend DataSupport` (a mixin is also available)
3. We ran codegen: `flutter packages pub run build_runner build`

```dart
@JsonSerializable()
@DataRepository([StandardJSONAdapter, JSONPlaceholderAdapter])
class Todo extends DataSupport<Todo> {
  @override
  final int id;
  final String title;
  final bool completed;

  Todo({ //... });
}
```

We now have a `TodoRepository` that we can retrieve with Provider:

```dart
final repository = context.read<Repository<Todo>>();
```

(We'll later see how we wired up Provider in literally _one line of code_.)

So where is the base URL `https://jsonplaceholder.typicode.com/` configured? 🤔

Answer: In a custom _adapter_!

```dart
mixin JSONPlaceholderAdapter<T extends DataSupport<T>> on StandardJSONAdapter<T> {
  @override
  String get baseUrl => 'https://jsonplaceholder.typicode.com/';
}
```

For more info on adapters, see [Adapters](#adapters).

### ➕ Creating a new TO-DO

We instantiate a new `Todo` model with a totally random title and save it:

```dart
FloatingActionButton(
  onPressed: () {
    Todo(title: "Task number ${Random().nextInt(9999)}").save();
  },
```

Done!

This sent a request in background to `POST https://jsonplaceholder.typicode.com/todos`

But... why can't we see this new `Todo` in the list?!

### ⚡️ Reactivity to the rescue

It's not there because we used a `FutureBuilder` which fetches the list _only once_.

The solution is making the list reactive – i.e. using `watchAll()`:

```dart
DataStateBuilder<List<Todo>>(
  notifier: context.read<Repository<Todo>>().watchAll(params: {'userId': '1', '_limit': '5'});
  builder: (context, state, _) {
    return ListView.builder(
      itemBuilder: (context, i) {
        if (state.isLoading) {
          return CircularProgressIndicator();
        }
        return Text('TO-DO: ${state.model.title}'),
      },
    );
  }
}
```

We'll use [`DataStreamBuilder`](https://pub.dev/packages/flutter_data_state) to access the state objects that carry our `Todo` models. It behaves pretty much like a `ValueListenableBuilder`.

Add `flutter_data_state` to your `pubspec.yaml` and run `flutter pub get` again.

Done? **Restart** the app (no hot-reload this time).

Creating a new TO-DO _will_ now show up:

![](docs/02a.png)

Before, with an `id=null` (temporary model which hasn't been persisted)

![](docs/02b.png)

After, with an `id=201` that was assigned by the API server.

Notice that we passed a `_limit=5` query param, so we only got 5 items!

Under the hood, we are using the [`data_state`](https://pub.dev/packages/data_state) package which essentially is a [`StateNotifier`](https://pub.dev/packages/state_notifier). In other words, a "Flutter-free ValueNotifier" that emits immutable `DataState` objects.

This new `Todo` appeared because `watchAll()` reflects the current **local storage** state. As a matter of fact, JSON Placeholder does not actually save anything.

Models are fetched from the network _in the background_ by default. (This strategy can be changed by overriding methods in a custom adapter!)

#### ⛲️ Prefer a Stream API?

No problem:

```dart
StreamBuilder<List<Todo>>(
  notifier: context.read<Repository<Todo>>().watchAll(params: {'userId': '1', '_limit': '5'}).stream;
  builder: (context, snapshot) {
    return ListView.builder(
      itemBuilder: (context, i) {
        final todo = snapshot.data[i];
        return Text('TO-DO: ${todo.title}'),
      },
    );
  }
}
```

**Check out the fully working app: https://github.com/flutterdata/flutter_data_todos**

### ♻ Reloading

For a minute, let's change that floating action button to _overwrite_ one of our TO-DOs. For example, `Todo` with id=1.

And now **Refresh** the app (no hot-reload for now).

```dart
FloatingActionButton(
  onPressed: () {
    Todo(id: 1, title: "OVERWRITING TASK!", completed: true).save();
  },
```

If we click on the `+` button we get:

![](docs/03.png)

As discussed before, JSON Placeholder does not persist any data. We'll verify that claim by reloading our data with a `RefreshIndicator` and the very handy `DataStateNotifier#reload()`!

```dart
RefreshIndicator(
  onRefresh: () async {
    await notifier.reload();
  },
```

![](docs/04a.png)

And the state of `Todo` with `id=1` has been reset!

![](docs/04b.png)


### ⛔️ Deleting a TO-DO

There's stuff "User 1" just doesn't want to do!

We can delete a `Todo` on dismiss:

```dart
onDismissed: (_) async {
  await todo.delete();
},
```

![](docs/05a.png)

Done! (well, not really "done" 😄)

![](docs/05b.png)

### ✅ Marking as done!

If we add a `GestureDetector` to our list's tiles, we can easily toggle the `done` state:

```dart
GestureDetector(
  onDoubleTap: () => todo.copyWith(completed: !todo.completed).save(),
```

![](docs/06.png)

All tasks done!

### 🎎 Relationships

Let's now slightly rethink our query. Instead of **"fetching all TO-DOs for user 1"** we are going to **"get user 1 with all their TO-DOs"**.

First, we have to create the `User` model:

```dart
@JsonSerializable()
@DataRepository([StandardJSONAdapter, JSONPlaceholderAdapter])
class User extends DataSupport<User> {
  @override
  final int id;
  final String name;
  final HasMany<Todo> todos;

  User({ //... });
}
```

Remember to generate its repository:

```
flutter packages pub run build_runner build
```

And now `Repository<User>` is available. We are going to request the API to embed the linked `Todo` models:

```dart
DataStateBuilder<User>(
  notifier: context.read<Repository<User>>().watchOne('1', params: {'_embed': 'todos'});
  builder: (context, state, _) {
    final user = state.model;
    return ListView.builder(
      itemBuilder: (context, i) {
        return Text('TO-DO: ${user.todos[i]} is for ${user.name}'),
      },
    );
  }
}
```

![](docs/01.png)

Yep, relationships between models are automagically updated!

They work even when data comes in at different times: when new models are loaded, relationships are automatically wired up.

**Check out the working app: https://github.com/flutterdata/flutter_data_todos**

## 🌎 Philosophy

 - Developer experience is paramount
 - Simple should be easy, complex should be possible
 - Scales well both up and down

### Features

 - reactive architecture ⚡️
 - transparent API access and serialization 📩
 - offline-first 🔌
 - magic relationship support 🎎
 - extremely configurable and composable 🧱
 - with minimal boilerplate!

### Compatibility

Fully compatible with the tools we know and love:

|                   | Compatible | Optional |
| ----------------- | ---------- | -------- |
| Flutter           | ✅          | Yes      |
| Flutter Web       | ✅(**)      | Yes      |
| Pure Dart         | ✅          | No       |
| json_serializable | ✅          | No       |
| Firebase          | ✅(*)       | Yes      |
| Firebase Auth     | ✅(*)       | Yes      |
| REST API + JSON   | ✅          | Yes      |
| JSON:API          | ✅          | Yes      |
| Provider / Hooks  | ✅          | Yes      |
| Streams / BLoC    | ✅          | Yes      |
| Freezed           | ✅          | Yes      |
| state_notifier    | ✅          | Yes      |
| Hive              | ✅          | No       |

(*) **Firebase and other adapters are coming soon!**

(**) Needs testing but there's no reason why it shouldn't

## 🔧 Installing and configuring

Add `flutter_data` to your `pubspec.yaml` file:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_data: ^0.3.1
```

Annotate your models with `@DataRepository()` and the corresponding mixins.

Then, trigger a build:

```
flutter packages pub run build_runner build
```

Flutter Data auto-generated the `main.data.dart` library so everything is ready for use. It makes the `dataProviders` method available, which will configure all the necessary Providers.

```dart
// main.dart

import 'package:flutter/material.dart';
import 'package:flutter_data/flutter_data.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:todo_app/main.data.dart';

void main() {
  runApp(MultiProvider(
    providers: [
      ...dataProviders(getApplicationDocumentsDirectory),
      // your providers here
    ],
    child: TodoApp(),
  ));
}

class TodoApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (context.watch<DataManager>() == null) {
      return Spinner();
    }
    // all Flutter Data providers are ready at this point
    final repository = context.read<Repository<Todo>>();
    return MaterialApp(
// ...
```

Not using Provider? Not using Flutter? No problem! The [cookbook](#-cookbookfaq) explains how to configure Flutter Data in your app.

## 👩🏾‍💻 API

### Repository API

The Repository public API is shown below. Fully fledged documentation is coming soon!

```dart
// returns a list of all users
Future<List<T>> findAll(
      {bool remote = true,
      Map<String, String> params,
      Map<String, String> headers});

// subscribe to updates (see the data_state package)
DataStateNotifier<List<T>> watchAll(
      {bool remote = true,
      Map<String, String> params,
      Map<String, String> headers});

// .stream can be called on a DataStateNotifier for
// obtaining a ValueStream

// returns just one user by ID
Future<T> findOne(dynamic id,
      {bool remote = true,
      Map<String, String> params,
      Map<String, String> headers})

DataStateNotifier<T> watchOne(dynamic id,
      {bool remote = true,
      Map<String, String> params,
      Map<String, String> headers});

// save
Future<T> save(T model,
      {bool remote = true,
      Map<String, String> params = const {},
      Map<String, String> headers});

// delete
Future<void> delete(dynamic id,
      {bool remote = true,
      Map<String, String> params,
      Map<String, String> headers});

// http and serialization

String baseUrl;

UrlDesign get urlDesign;

Map<String, String> get headers => {};

Map<String, dynamic> serialize(T model);

Iterable<Map<String, dynamic>> serializeCollection(Iterable<T> models) => models.map(serialize);

T deserialize(dynamic object, {String key});

Iterable<T> deserializeCollection(object);

Future<R> withHttpClient<R>(OnRequest<R> onRequest);

FutureOr<R> withResponse<R>(http.Response response, OnResponseSuccess<R> onSuccess);
```

#### Adapters

Flutter Data is extremely configurable and composable.

The default `Repository` behavior can easily be customized via adapters (Dart mixins `on Repository<T>`).

A simple example would be:

```dart
mixin JSONPlaceholderAdapter<T extends DataSupport<T>> on StandardJSONAdapter<T> {
  @override
  String get baseUrl => 'https://jsonplaceholder.typicode.com/';
}
```

We simply have to add adapters as parameters to `@DataRepository()`. No need to pollute our models with a thousand annotations!

```dart
@DataRepository([StandardJSONAdapter, JSONPlaceholderAdapter]);
```

Our own `JSONPlaceholderAdapter` is _customizing_ the `StandardJSONAdapter` which ships with Flutter Data (notice `on StandardJSONAdapter<T>` which in turn applies `on Repository<T>`). **Order matters!**

There are three bundled adapters in Flutter Data that demonstrate how powerful this concept is:

 - [StandardJSONAdapter](https://github.com/flutterdata/flutter_data/blob/master/lib/src/adapter/remote/standard_json_adapter.dart)
 - [JSONAPIAdapter](https://github.com/flutterdata/flutter_data/blob/master/lib/src/adapter/remote/json_api_adapter.dart)
 - [OfflineAdapter](https://github.com/flutterdata/flutter_data/blob/master/lib/src/adapter/remote/offline_adapter.dart)

Of course, these all can be combined!

Adapters for Wordpress or Github REST access, or even a [JWT authentication adapter](#adapter-example-jwt-authentication-service) are easy to build.

There are many more adapter examples in the [cookbook](#cookbookfaq).
 
### DataSupport and Relationships API

```dart
@JsonSerializable()
@DataRepository([JSONAPIAdapter, BaseAdapter])
class Appointment extends DataSupport<Appointment> {
}
```

Extending `DataSupport` in your models gives access to handy extensions:

```dart
String get key;

Future<T> save(
    {bool remote = true,
    Map<String, String> params = const {},
    Map<String, String> headers});

Future<void> delete(
    {bool remote = true,
    Map<String, String> params = const {},
    Map<String, String> headers});

Future<T> load(
    {bool remote = true,
    Map<String, String> params,
    Map<String, String> headers});

DataStateNotifier<T> watch(
    {bool remote = true,
    Map<String, String> params,
    Map<String, String> headers});

bool get isNew;
```

An alternative exists: `DataSupportMixin`, but model initialization MUST be done manually. For example:

```dart
final post = Post(title: 'new post').init();
```

Note that, for the time being, `fromJson` MUST be included in models:

```dart
@JsonSerializable()
@DataRepository([JSONAPIAdapter, BaseAdapter])
class Appointment extends DataSupport<Appointment> {
  // ...
  factory Appointment.fromJson(Map<String, dynamic> json) =>
      _$AppointmentFromJson(json);
}
```

#### Saving and deleting a model

```dart
final user = await User(name: 'Frank Treacy').save();

// which is syntax sugar for
final user = await repository.save(User(name: 'Frank Treacy'));

// only save locally
await User(name: 'Frank Treacy').save(remote: false);

// delete user
await user.delete();
```

#### Using relationships

Flutter Data has a powerful relationship mapping system.

Provided the API responds correctly with relationship data,
we can expect the following to work:

```dart
// recall that User has a HasMany<Todo> attribute
User user = await repository.findOne('Frank');

Todo todo = user.todos.first;

print(todo.title); // write Flutter Data docs

print(todo.user.value.name); // Frank

// or

final family = Family(
      surname: 'Kamchatka',
      house: BelongsTo(House(address: "Sakharova Prospekt, 19"))
    );
print(family.house.value.families.first.surname);  // Kamchatka
```

## 👩‍🍳 Cookbook/FAQ

### Configuration without Provider

```dart
// main.dart

import 'package:flutter/material.dart';
import 'package:flutter_data/flutter_data.dart';
import 'package:path_provider/path_provider.dart';
import 'package:todo_app/main.data.dart';

void main() {
  runApp(Center(child: const CircularProgressIndicator()));

  final baseDir = await getApplicationDocumentsDirectory();
  final manager = await FlutterData.init(baseDir);
  Locator locator = manager.locator;

  runApp(MaterialApp(
    // ...
    final repository = locator<Repository<User>>();
    // ...
  ));
}
```

`Locator` is a typedef suggested by [Remi Rousselet](https://twitter.com/remi_rousselet):

```dart
typedef Locator = T Function<T>();
```

Any conforming type can be used:

 - the bundled `locator` shown above
 - a `get_it` locator
 - `context.read` from the Provider package

### Configuration for pure Dart projects (no Flutter)

```dart
void main() async {
  Directory _dir;

  try {
    _dir = await Directory('/tmp/myapp').create();
    final manager = await FlutterData.init(_dir);
    Locator locator = manager.locator;
    
    final repository = locator<Repository<User>>();
    
    // ...

  } finally {
    await _dir.delete(recursive: true);
  }
}
```

### Is it compatible with Freezed?

Yes. Actually, Flutter Data's integration tests (and the TO-DOs example app) run off Freezed immutable models.

Here's an example:

```dart
@freezed
@DataRepository([JSONAPIAdapter, BaseAdapter])
abstract class City extends DataSupport<City> implements _$City {
  City._();
  factory City({dynamic id, String name}) = _City;
  factory City.fromJson(Map<String, dynamic> json) => _$CityFromJson(json);
}
```

If you need your ID to be of a specific type such as `String`, make it `extends IdDataSupport<String, City>` instead.

`IdDataSupport` is not needed for classic immutable models.

### Adapter example: Headers

```dart
mixin BaseAdapter<T extends DataSupportMixin<T>> on Repository<T> {
  final _localStorageService = manager.locator<LocalStorageService>();

  @override
  get baseUrl => "http://my.remote.url:8080/";

  @override
  get headers {
    final token = _localStorageService.getToken();
    return super.headers..addAll({'Authorization': token});
  }
}
```

All `Repository` public methods like `findAll`, `save`, `serialize`, `deserialize`, ... are available.

### Adapter example: JWT authentication service

```dart
mixin AuthAdapter<DataSupportMixin> on Repository<User> {
  Future<String> login(String email, String password) async {
    final response = await withHttpClient(
      (client) => client.post(
        '$baseUrl/token',
        body: _serializeCredentials(user, password),
        headers: headers,
      ),
    );

    final map = json.decode(response.body);
    return map['token'] as String;
  }
}
```

Now this adapter can be configured and exposed *just* on the `User` model:

```dart
@JsonSerializable()
@DataRepository([StandardJSONAdapter, BaseAdapter, AuthAdapter])
class User extends DataSupport<User> {
  // ...
}
```

And use it in a widget or BLoC:

```dart
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final Repository<User> _repository;
  AuthBloc(this._repository);

  @override
  Stream<AuthState> mapEventToState(
    AuthEvent event,
  ) async* {
    yield* event.map(
      login: (e) async* {
        final user = await (_repository as AuthAdapter).login(e.email, e.password);
        yield AuthState(user);
      },
```

### Adapter example: The stupid adapter

Appends `zzz` to any ID:

```dart
mixin StupidAdapter<T extends DataSupportMixin<T>> on Repository<T> {
  @override
  Future<T> findOne(String id,
      {bool remote = true,
      Map<String, String> params,
      Map<String, String> headers}) {
        return super.findOne('${id}zzz', remote: remote, params: params, headers: headers);
      }
}
```

### Can the HTTP client be overriden?

Yes. Override `withHttpClient`.

Example:

```dart
mixin HttpProxyAdapter<T extends DataSupportMixin<T>> on Repository<T> {
  final _httpClient = HttpClient();
  IOClient _ioClient;

  @override
  Future<T> withHttpClient<T>(fn) {
    _httpClient.findProxy = (uri) => "PROXY http://proxy.url";
    _ioClient = IOClient(_httpClient);
    return fn(_ioClient);
  }

  @override
  Future<void> dispose() {
    _ioClient.close();
    return super.dispose();
  }
}
```

### Does Flutter Data depend on Flutter?

No! Despite its name this library does not depend on Flutter at all.

See the `example` folder for an, uh, example.

### How do I get hold of Repositories with Provider?

Remember to use `context.read<Repository<T>>()` (or `Provider.of<Repository<T>>(listen: false)`) as repositories don't change.

### Offline support

Use or extend the provided [offline adapter](https://github.com/flutterdata/flutter_data/blob/master/lib/src/adapter/remote/offline_adapter.dart).

### Can I group adapter mixins into one?

No. https://stackoverflow.com/questions/59248686/how-to-group-mixins-in-dart

### Where does Flutter Data generate code?

 - in `*.g.dart` files (part of your models)
 - in `main.data.dart` (as a library)

### Can I use mutable classes?

Immutable models are strongly recommended, equality is very important for things to work well. Use data classes like freezed or equality tools.

It is possible to use mutable classes such as `ChangeNotifier`s. However, `id` MUST be a `final` field (or at least not have a setter).

Even then, it is recommended to have relationships (`BelongsTo`, `HasMany`) as final fields. If they are reassigned via a setter, the model MUST be manually reinitialized (`repository.syncRelationships(model)`) or relationship mappings WILL break.

### Why is model.save() not available?

`DataSupport` extensions are syntax sugar and will ONLY work when importing Flutter Data in the corresponding file:

```dart
import 'package:flutter_data/flutter_data.dart';
```

### Local storage for long term persistence

tl;dr don't save anything critical (with Flutter Data) just yet

  - Flutter Data is in alpha state and therefore there are no guarantees: APIs WILL change, local formats WILL change (this is why `clear=true` by default, meaning that local storage will be wiped out when the app restarts)
  - Additionally, we are waiting until Hive 2 comes out

### How can I declare the inverse relationship?

At the moment, the inverse relationship is looked up by type and it's not configurable. This will be fixed.

### Is Flutter Data a state management solution?

Yes. It is essentially a stream/stream controller combo. Couple it with a DI like Provider or get_it (or the included service locator) and you're set.

Want to use streams? Call `repo.watchAll().stream`.

Want to use `StateNotifier`s? Call `repo.watchAll()`.

https://www.reddit.com/r/FlutterDev/comments/fto3nt/use_hive_db_instead_of_other_state_management/

### Polymorphism

```dart
abstract class User<T extends User<T>> extends DataSupport<T> {
  final String id;
  final String name;
  User({this.id, this.name});
}

@JsonSerializable()
@DataRepository([JSONAPIAdapter, BaseAdapter])
class Customer extends User<Customer> {
  final String abc;
  Customer({String id, String name, this.abc}) : super(id: id, name: name);
}

@JsonSerializable()
@DataRepository([JSONAPIAdapter, BaseAdapter])
class Staff extends User<Staff> {
  final String xyz;
  Staff({String id, String name, this.xyz}) : super(id: id, name: name);
}
```

## 📲 Apps using Flutter Data

![](docs/scout.png)

The new offline-first [Scout](https://scoutforpets.com) Flutter app is being developed in record time with Flutter Data.

<!-- omit in toc -->
## ➕ Questions and collaborating

Please use Github to ask questions, open issues and send PRs. Thanks!

You can also hit me up on Twitter [@thefrank06](https://twitter.com/thefrank06)

Tests can be run with: `pub run test`

<!-- omit in toc -->
## 📝 License

See [LICENSE](https://github.com/flutterdata/flutter_data/blob/master/LICENSE).