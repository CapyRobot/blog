---
title: Structuring a C++ Application - The order is a graph, not a list
id: the-order-is-a-graph
date: 2026-11-17
tags:
 - C++
enable_comments: true
description: Startup and shutdown order is a property of the dependency graph, and a hand-written order is a copy of it that drifts. How declared dependencies let the compiler derive the order, report cycles by name, and roll back a failed startup; init/deinit vs start/stop; Optional and After edges; and why a service locator with checked dependencies loses most of what made it an anti-pattern.
---

1. {% post_link keel_1 %}
2. ► {% post_link keel_2 %}

---

## Where We Left Off

A quick recap, in case you skipped the first post. If you didn't, you can skip this section.

I built [keel](https://github.com/mcreduardo/keel), a library implementation of the design described in these posts. I use it to write the examples below. The design is simple enough for you to build it yourself.

An application is made of *components*: coarse objects that live as long as the application, own a resource or hide a decision, and have a lifecycle. One place, the *composition root*, lists them and owns them. Each component declares what it uses on its class line, as types, and the compiler checks both sides: a component can't reach what it didn't declare, and the application can't leave out what somebody needs.

```cpp
class Logger : public keel::Component<Config> {
    Logger() {
        config_ = &getComponent<Config>(); // Only compiles because Config is explicitly listed as a dependency
    }
    ...
};
```

The example was `telemetryd`, a small agent that reads samples from a few devices, aggregates them on a worker pool, and exports a summary. Its composition root was one line, with the components in the "wrong" order on purpose:

```cpp
using Telemetryd = keel::App<Exporter, Aggregator, WorkerPool, DeviceManager, Logger, Config, CliArgs>;
```

And it still came up and went down in the right order: the logger first and the worker pool after it, then the reverse on shutdown, every time. I promised to explain how. I also left a warning in that post: if you build this yourself, the easy version keeps the order of the lines, and that rebuilds the bug the whole design was supposed to remove.

That warning is where this post starts. Why is the order of the lines a trap? And if the order doesn't come from the lines, where does it come from?

## The Ordering Trap

Here's a story I've seen in more than one codebase in different variations.

An application has run fine for months. Then it starts crashing on shutdown, rarely, only on some machines. The change that triggered it touched neither of the components in the stack trace. Someone added a new component at the end of the startup list, or moved a member somewhere else, or refactored a big `init()` in smaller pieces. The crash is in a destructor, or in a thread that is still running after something it uses has been torn down.

When you finally find it, the fix is one line: move a declaration or swap two calls. The answer is usually that it worked by accident or relied on a manual representation of the dependency graph.

Here's a variant I find even more instructive. A component declares a dependency on another, but is listed *before* it in `main()`. It works anyway, because it first touches the dependency in a later phase, after everything is up. Then someone moves one lookup into the earlier phase, which is a perfectly reasonable refactor, and it breaks. Meanwhile, a test harness and a command-line tool build the same components in two other orders, and each one has its own version of the assumption.

This is a possible hand-ordered version of three of `telemetryd`'s components:

```cpp
void runDaemon() {
    Config config;
    Logger logger;
    WorkerPool pool;
    config.init();
    logger.init(config);
    pool.init(config, logger);
    // ... run ...
    // no explicit deinit - deinit happens in the destructor
    // pool's destructor first, it was constructed last
    // logger's destructor second, it was constructed second
}
```

It's correct. `pool` stops using the logger before its destructor runs. Now someone add an explicit logger deinit to address a backend change.

```cpp
void runDaemon() {
    ...
    Logger logger;
    WorkerPool pool;
    ...
    logger.init(config);
    pool.init(config, logger);
    // ... run ...
    logger.deinit(); // logger is no longer available
}
```

It compiles. With `-Wall -Wextra`, Clang has nothing to say. It runs, too:

```
[error] logger down! worker pool is still trying to write to it!!!
```

Here the logger is a toy that notices; a real one could write into a closed file, or crash.

### Four orders, kept by hand

Why is this so easy to get wrong? Because there isn't one order. There are four: **construction, initialization, start and shutdown**. Construction and initialization go in dependency order. Shutdown goes in reverse, and has its own phases: stop the activity first, then release resources, then destroy. A hand-written version keeps each of these lists separately, in different places, in different styles: member declarations, an `init()` function, a shutdown function, a destructor. Each one is a copy of the same graph, and nothing checks that they agree.

C++ developers have seen this problem before, one level down. The [static initialization order fiasco](https://isocpp.org/wiki/faq/ctors#static-init-order) is the same bug: globals in different translation units depend on each other, and the language gives no order between them. John Lakos warned about it in *Large-Scale C++ Software Design* back in 1996. The standard advice is to avoid the situation: no non-trivial globals that depend on each other, a thin `main()` that creates everything in order. That's good advice, and it moves the problem into `main()`. Which is where we are.

### Shutdown is the hardest half

Startup bugs are loud. Issues usually fail immediately, on every run, on the developer's machine. Shutdown bugs are quiet. Sometimes even irrelevant and ignored.

By the time you shutdown, threads are running, timers are armed, callbacks are registered with things you don't own. A component that is torn down while a thread still uses it doesn't fail deterministically. It fails when the timing lines up, which is rarely on your machine and often in the field. And shutdown code is the least tested code in most applications: tests start the application, check something, and let the process exit.

There's another reason shutdown is harder: it can't really fail. If a database connection fails to close, what do you do? Retry? Abort the shutdown? You're already leaving. That's why keel's `stop()` and `deinit()` are `noexcept`, just like destructors. An override without `noexcept` doesn't compile. A component whose cleanup can fail handles it itself, or logs it. The framework never has to decide what a half-finished shutdown means, because there is no such thing.

## `start()` and `stop()`: When Activity Begins and Ends

The first post used only two hooks, `init()` and `deinit()`, and said that `start()` and `stop()` exist. Here is what they're for.

A component's life has two different pairs of events:

- **Resources.** Construction stores the arguments. `init()` acquires resources: opens
  files and devices, binds sockets, reads settings, resolves dependencies. `deinit()`
  releases them.
- **Activity.** `start()` begins doing things: launches threads, accepts connections, arms
  timers, sends the first packet. `stop()` ends that activity.

The point of the split is in two guarantees. `start()` runs only after every component in the application has finished `init()`, not just the ones this component depends on. And `stop()` runs for every component before any `deinit()`. So no component starts doing work while something in the application is half set up, and no component releases a resource while anything in the application is still active.

Why not do this in constructors and destructors? A member-initializer list orders construction, and destruction in reverse. It has no way to say "the exporter must not send before everything it reads from is ready", or "the worker pool must stop running jobs before the logger it writes to goes away". Those are statements about activity, and they span the whole application, not just one object and its members.

Here's `telemetryd`'s worker pool, now with its threads in the right hooks:

```cpp
class WorkerPool : public keel::Component<Config, Logger> {
    void init() override {
        // keel: the Logger and Config components are guaranteed to be initialized
        logger_ = &getComponent<Logger>();
        num_workers_ = getComponent<Config>().workers();
    }
    void start() override {
        // keel: the Logger and Config components are guaranteed to be started
        for (int i = 0; i < num_workers_; ++i) threads_.emplace_back([this] { work(); });
        logger_->info("worker pool started, " + std::to_string(num_workers_) + " threads");
    }
    void stop() noexcept override {
        // keel: the Logger and Config components are guaranteed **to have not** been stopped yet
        // ... set done_, wake every thread ...
        for (auto& t : threads_) t.join();
        logger_->info("worker pool stopped");  // the Logger is still up
    }
};
```

And the exporter, which now connects to its endpoint when it starts:

```cpp
void Exporter::start() {
    if (offline_) {
        logger_->error("exporter cannot connect to " + endpoint_);
        throw std::runtime_error("cannot connect to " + endpoint_);
    }
    logger_->info("connected to " + endpoint_);
}
void Exporter::stop() noexcept { logger_->info("disconnected from " + endpoint_); }
```

The rules are the same ones as for `init()` and `deinit()`. `start()` runs in dependency order, `stop()` in reverse. `init()` and `start()` may throw. If one does, keel rolls back: it stops what has started, in reverse, deinitializes everything that was initialized, in reverse, and rethrows your exception unchanged. One rule covers both phases: **a failed startup leaves nothing running and nothing held.**

Run `telemetryd` with the endpoint unreachable, and the exporter's `start()` throws:

```
[info] logger up, config telemetryd.conf
[info] opened imu0
[info] opened gps0
[info] opened baro0
[info] aggregating 3 devices
[info] worker pool started, 2 threads
[error] exporter cannot connect to collector.local:9000
[error] keel: component start failed with std::runtime_error, rolling back...
[info] worker pool stopped
[info] closed imu0
[info] closed gps0
[info] closed baro0
[info] logger down
```

The worker pool had already started, so it is stopped. The devices were opened, so they are closed. The logger goes last, and logs everybody's goodbyes. The exporter itself gets no `stop()`, because it never started; if `start()` throws, the component undoes its own partial work before throwing. Nobody wrote rollback code for this application. It falls out of the order.

`main()` didn't change from the first post:

```cpp
return keel::run<Telemetryd>(&Exporter::run, argc, argv);
```

`keel::run` constructs the application, then runs `init()`, `start()`, `Exporter::run()`, `stop()` and `deinit()`, in that order, and shuts down even if `Exporter::run()` throws.

Most components don't need `start()` and `stop()`. A config, a logger, a cache: `init()` and maybe `deinit()` are enough. The hooks are there for the ones that own activity. Sometimes, entire applications do not need it and both hooks can be completely omitted.

Here is the whole sequence, for any application. It's not keel's code exactly, but it's what keel does.

```cpp
App app{args...};
    //< constructs every component, in dependency order
    //< in case of failure, RAII handles cleanup

std::size_t initialized = 0, started = 0;
std::exception_ptr error;
try {
    for (auto& c : components) { c.init(); ++initialized; }
    for (auto& c : components) { c.start(); ++started; }
    result = fn();  // Exporter::run(): runs until shutdown
} catch (...) {
    error = std::current_exception();
}
for (auto& c : reverse(first(components, started))) c.stop();        // noexcept
for (auto& c : reverse(first(components, initialized))) c.deinit();  // noexcept
if (error) std::rethrow_exception(error);
return result;  // and app destroys every component, in reverse
```

There is one way down, whatever happened on the way up. A component is stopped only if it started, and deinitialized only if it initialized. Construction needs no rollback code: the components are members of the `App`, so if a constructor throws, C++ destroys the ones already built, in reverse, like any other members.

## The Order Is a Graph, Not a List

So where does the order come from? From the declarations you already wrote. You can write it by hand correctly, but you simply do not need to.

Every component lists its dependencies on its class line.

```cpp
class Config : public keel::Component<CliArgs> { /* ... */ };
class Logger : public keel::Component<Config> { /* ... */ };
class WorkerPool : public keel::Component<Config, Logger> { /* ... */ };
class Aggregator : public keel::Component<DeviceManager, WorkerPool, Logger> { /* ... */ };
```

Each entry is an edge: `WorkerPool` needs `Config` and `Logger` before it. Together, the class lines *are* the dependency graph. Nobody has to draw it or maintain it separately.

An order in which every component comes after its dependencies is a topological order of that graph, and computing one is a textbook algorithm. The one keel uses is Kahn's, from 1962: repeatedly pick a component whose dependencies have all been placed, place it, and repeat. If at some point nothing can be placed but components are left, they're waiting on each other, and that's a cycle.

The composition root lists the components in any order:

```cpp
using Telemetryd = keel::App<ReadyNotifier, Exporter, Metrics, Aggregator, WorkerPool, DeviceManager, Logger,
                             Config, CliArgs>;
```

(Two of these are new; I'll get to `Metrics` and `ReadyNotifier` below) The order keel derives is available as a `constexpr` array, `Telemetryd::initOrder()`. Printing it:

```
CliArgs
Config
Logger
Metrics
WorkerPool
DeviceManager
Aggregator
Exporter
ReadyNotifier
```

And here's the graph, drawn by `toDot()` from the same declarations, with that order on the nodes:

![telemetryd's dependency graph, with the derived init order numbered on each node: 1 CliArgs, 2 Config, 3 Logger, 4 Metrics, 5 WorkerPool, 6 DeviceManager, 7 Aggregator, 8 Exporter, 9 ReadyNotifier](/images/posts/keel_2/telemetryd2-graph.svg)

That one order drives everything. Construction, `init()` and `start()` go forward through it. `stop()`, `deinit()` and destruction go backwards. It's computed once, from one source, so any order derived from the declarations can't disagree with each other. Every `init()` before any `start()`; every `stop()` before any `deinit()`; each phase in dependency order, or its reverse.

### Ties keep the list order

A graph usually has more than one valid topological order. `Metrics` and `WorkerPool` both depend only on things below them, and not on each other; either could go first. Which one does?

keel always places the earliest ready component in the composition list. `Metrics` is listed before `WorkerPool`, so it goes first. Swap them in the list and they swap in the order. Nothing else moves.

That sounds like a detail, but it matters in practice. It means the order is **deterministic**: same declarations, same list, same order, on every machine and every compiler. Boots are reproducible, so two logs from two runs can be diffed line by line. And when something does depend on the order of independent components, at least it fails the same way every time.

But don't rely on it. If two components need an order, that's an edge, and it belongs in a declaration. Below I show how to write one without pretending to use the other component.

## Doing It at Compile Time

keel computes the order at compile time. The components are types, the graph is a `constexpr` adjacency matrix built from their lists, and the sort is a `constexpr` function. Here's the idea, stripped down to about twenty-five lines. Each component exposes its dependencies as a `TypeList`:

```cpp
// Row of the adjacency matrix for one component: dependsOn[j] is true if it lists Cs[j].
template <class... Cs, class... Deps>
constexpr std::array<bool, sizeof...(Cs)> dependsOn(TypeList<Cs...>, TypeList<Deps...>) {
    std::array<bool, sizeof...(Cs)> row{};
    ((row[indexOf<Deps, Cs...>()] = true), ...);
    return row;
}

template <class... Cs>
constexpr std::array<std::size_t, sizeof...(Cs)> initOrder() {
    constexpr std::size_t N = sizeof...(Cs);
    // build the adjacency matrix
    const std::array<std::array<bool, N>, N> graph{dependsOn(TypeList<Cs...>{}, typename Cs::Deps{})...};
    std::array<std::size_t, N> waiting{}, order{};
    std::array<bool, N> placed{};
    // count the number of dependencies for each component
    for (std::size_t i = 0; i < N; ++i){
        for (std::size_t j = 0; j < N; ++j) {
            waiting[i] += graph[i][j];
        }
    }
    // place the components in the order
    for (std::size_t k = 0; k < N; ++k) {
        std::size_t next = 0;  // the earliest ready component keeps ties in list order
        while (next < N && (placed[next] || waiting[next] != 0)) ++next;
        if (next == N) throw "dependency cycle";  // not a constant expression: compile error
        placed[next] = true;
        order[k] = next;
        for (std::size_t i = 0; i < N; ++i) waiting[i] -= graph[i][next];
    }
    return order;
}

constexpr auto order = initOrder<Exporter, WorkerPool, Logger, Config, CliArgs>();
static_assert(order == std::array<std::size_t, 5>{4, 3, 2, 1, 0});  // CliArgs first
```

That's dense, but ordinary C++20. No template recursion, no type-level tricks beyond one fold expression: a loop, inside a function the compiler runs. Once the order is a `constexpr` array, building the application in that order is a matter of an index sequence. (The full sketch, with the test types, is in the post's examples. keel's real version also handles some extra features which I will discuss later like `Optional<T>` and `After<T>`.)

It's O(N²), which may sound bad. But components are coarse, a few tens per application, and the cost is in compile time, not runtime. keel's test with 150 components (a lot), each with up to five dependencies, compiles in about a second on my Macbook Pro M4 with Clang. I'll take that for an order that can't be wrong.

### Cycles, named

The sketch detects a cycle by giving up: when nothing can be placed, it reaches a `throw`, which can't run at compile time, so compilation fails. Here's what that looks like:

```
topo_sort_sketch.cpp:71:16: error: constexpr variable 'cycle' must be initialized by a constant expression
   71 | constexpr auto cycle = initOrder<P, Q>();
      |                ^       ~~~~~~~~~~~~~~~~~
topo_sort_sketch.cpp:43:24: note: subexpression not valid in a constant expression
   43 |         if (next == N) throw "dependency cycle";  // not a constant expression: compile error
```

It's correct, and nearly useless. It tells you there's a cycle somewhere. In a composition of forty components, "somewhere" is not an answer.

Let's make a real one. `Config` would like to log that it loaded the file, so someone adds `Logger` to its list. But `Logger` reads its level from `Config`:

```cpp
class Config : public keel::Component<CliArgs, Logger> {  // Config now logs, but Logger reads Config
```

```
keel.hpp:930:19: error: static assertion failed due to requirement
'fixed<keel::detail::DependencyCycle<keel::detail::TypeList<Logger, Config>>>':
keel: dependency cycle among the components in DependencyCycle<TypeList<...>>
```

`DependencyCycle<TypeList<Logger, Config>>`. The two components on the cycle, and nothing else. Notice what's *not* in that list: every other component in `telemetryd` depends on `Logger` or `Config`, so none of them can be placed either. A naive report would name eight of the nine. keel names only the components that are actually on a cycle, which is the part you have to change.

Finding them is a second algorithm, Kosaraju's, which finds the [strongly connected components](https://en.wikipedia.org/wiki/Kosaraju%27s_algorithm) of the graph: groups of nodes that can all reach each other. A group of two or more is a cycle. It also runs at compile time, but only when the sort fails. A valid application never pays for it.

The fix is a design decision, and the error doesn't make it for you. Here, `Config` can return the message and let the caller log it, or the logger can start with a default level and pick up the configured one later. Usually one direction of a cycle is a call that should be a callback, two components that should be one, or a component that should be two (break `A` into `A + C`; `A <-> B` becomes `A -> C`, `B -> C`, and maybe `A -> B`; acyclical).

### One mistake, one error

I care about this a lot. The first version of these checks reported a missing dependency in about 1,500 characters. It was correct but too noisy.

I put some extra effort so every mistake keel can detect is a class template named after the mistake, with the types involved as its arguments: `MissingDependency<Aggregator, WorkerPool>`, `DependencyCycle<TypeList<Logger, Config>>`, `AmbiguousDependency<Service, Storage, ...>`. Checks that pass instantiate nothing, so a failure type exists only when it's the mistake, and its name is in the first line of the error, where the compiler prints the failed `static_assert`. The message after it says what the mistake means. And each mistake produces exactly one error. One cycle is one error, not one per component on it, and not one for every component downstream that now can't be placed.

Why does that matter so much? Because the alternative is the reason many C++ developers distrust compile-time frameworks. They've seen the error messages: three screens of template instantiation, and the actual mistake somewhere in the middle, spelled in types nobody wrote. If the compiler is going to check your architecture, its error messages are the user interface of the architecture. They had better be good.

The same goes for coding agents, for what it's worth. An agent that gets `MissingDependency<Aggregator, WorkerPool>` fixes the composition. An agent that gets three screens of templates could start editing the wrong file.

### The honest limits

**Complete types are needed for composition.** A component's header can list forward-declared types. But the composition root needs every component fully defined, because that's where keel reads the lists. That's what you want anyway: the composition root is the one place that knows everything.

```cpp
// a.hpp
class B;
class A : public keel::Component<B> {
    ...
    B* b_ = nullptr;
};

// a.cpp
#include "a.hpp"
#include "b.hpp" // Dependencies need to be complete in the implementation file

void A::init() {
    b_ = getComponent<B>();
}

// main.cpp
#include "a.hpp"
#include "b.hpp"

using MyApp = keel::App<A, B>; // All components must be complete in the composition root
```

**Errors still come with instantiation notes.** The first line names the mistake; the notes after it still walk through keel's internals. And there are a few corners where a message is less direct than I'd like.

**Compile-time cost is real, just small.** O(N²) in the number of components. Fine for tens or a hundred. MSVC's default `constexpr` step limit is about ten times lower than Clang's, so a composition of around a hundred components or more needs a flag there.

## Not Every Edge Is a Use: `Optional<T>` and `After<T>`

So far, every edge meant "I use this, so it comes first". Real applications have some other kinds of edges, and conflating them is how hand-written orders get their worst comments (`"// must be after X, don't ask"`).

### `Optional<T>`: use it if it's there

`telemetryd` now has a `Metrics` component that counts things. The exporter would like to count exports, but it can live without metrics: a debug build, a test, a stripped-down deployment might not compose `Metrics` at all.

```cpp
class Exporter : public keel::Component<Aggregator, Config, CliArgs, Logger, keel::Optional<Metrics>> {
    // ...
    void init() override {
        // ...
        metrics_ = findComponent<Metrics>();  // nullptr if Metrics isn't composed
    }
    int run() {
        // ... in the loop:
        if (metrics_ != nullptr) metrics_->count("exports");
    }
};
```

`findComponent<T>()` returns a pointer, `nullptr` if `Metrics` isn't composed. If it is, it comes before the exporter, like any dependency. Remove `Metrics` from the composition root, and the application still compiles and runs.

The access matches the promise. On an `Optional<T>`, `getComponent<T>()` (which returns a reference) doesn't compile, and the error tells you what to use instead:

```bash
keel.hpp:539:27: error: static assertion failed due to requirement
'!detail::contains<Metrics, keel::detail::TypeList<Metrics>>':
keel: T is declared keel::Optional<T>; use findComponent<T>(), which may return nullptr
telemetryd2.cpp:261:21: note: in instantiation of function template specialization
'keel::Component<Aggregator, Config, CliArgs, Logger, keel::Optional<Metrics>>::getComponent<Metrics>' requested here
```

### `After<T>`: order without access

The second kind of edge is the one hand-written lists are full of: "this must come after that", where *this* never calls *that*.

`telemetryd` runs under a supervisor (systemd, say), which wants to know when the service is actually ready, so that it can start the things that depend on it. "Ready" means the exporter is connected. A `ReadyNotifier` component sends that signal in its `start()`. It must start after the exporter has started. But it never calls the exporter; it has nothing to ask it.

You could list `Exporter` as a dependency and never use it. That's a lie on the class line: a reader could think it's a use, and it ties the notifier to the exporter's API for no reason. keel has a separate entry for it:

```cpp
class ReadyNotifier : public keel::Component<Logger, keel::After<Exporter>> {
    void init() override { logger_ = &getComponent<Logger>(); }
    void start() override {
        logger_->info("ready");  // a real service would call sd_notify("READY=1") here
    }
    void stop() noexcept override { logger_->info("stopping"); }

    const Logger* logger_ = nullptr;
};
```

`After<Exporter>` is an edge for ordering only: the notifier is constructed, initialized and started after the exporter, and stopped, deinitialized and destroyed before it.

"Ready", before the worker pool runs and before the exporter has a connection. A supervisor would start the services that depend on `telemetryd` against an exporter that may still fail to connect.

There's no access. Try it:

```cpp
    void start() override {
        getComponent<Exporter>();
        // ...
```

```bash
keel.hpp:541:27: error: static assertion failed due to requirement
'!detail::contains<Exporter, keel::detail::TypeList<Exporter>>':
keel: T is declared keel::After<T>, which is ordering only; replace it with T to use T
telemetryd2.cpp:291:9: note: in instantiation of function template specialization
'keel::Component<Logger, keel::After<Exporter>>::getComponent<Exporter>' requested here
```

And if `Exporter` isn't composed at all, `After<Exporter>` does nothing. There's nothing to come after.

The name is not an accident. It's the same split systemd makes between `Requires=` and `After=`. In the [systemd.unit](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html) manual: "Note that requirement dependencies do not influence the order in which services are started or stopped." A unit can require another without an order, or be ordered after another without requiring it. systemd has been managing the lifecycle of whole services for a long time, and it found it needed both words. So do components.

### Three words, three promises

I chose three separate entries instead of one with flags because each one is a different promise, made to a different reader.

| You write | It promises | Access | Checked |
|---|---|---|---|
| `T` | "I use `T`; I can't work without it." | `getComponent<T>()`, a reference | `T` must be composed |
| `keel::Optional<T>` | "I use `T` if it's there." | `findComponent<T>()`, a pointer | `getComponent` doesn't compile |
| `keel::After<T>` | "I come after `T`, but don't touch it." | none | any access doesn't compile |

All three order the same way: if `T` is there, it comes first. What differs is what the component may do with it, and the compiler holds each component to what it declared. A reviewer reading `keel::Component<Logger, keel::After<Exporter>>` knows, without opening the `.cpp`, that the notifier logs and that its timing depends on the exporter, and nothing else.

## "Isn't This a Service Locator?"

Yes. `getComponent<T>()` looks up a component at runtime, by type, from a registry the application owns. That's a service locator. Now let's take the objection seriously.

### The case against, stated fairly

Mark Seemann's [Service Locator is an Anti-Pattern](https://blog.ploeh.dk/2010/02/03/ServiceLocatorisanAnti-Pattern/) is the classic statement. His point is that a service locator "hides a class' dependencies, causing run-time errors instead of compile-time errors". You can't tell from a class's API what it needs. You find out when a lookup fails in production. And since the dependencies aren't part of the API, it's unclear when a change to them is a breaking change. In a later post he sharpens it: [Service Locator violates encapsulation](https://blog.ploeh.dk/2015/10/26/service-locator-violates-encapsulation/), "because it hides the preconditions for correct use." The class lies about what it needs.

His answer is constructor injection, wired in one place, by hand if possible. He calls that [Pure DI](https://blog.ploeh.dk/2014/06/10/pure-di/): "Dependency Injection without a DI Container." The longer version is in the book he wrote with Steven van Deursen, [*Dependency Injection: Principles, Practices, and Patterns*](https://www.manning.com/books/dependency-injection-principles-practices-patterns). I agree with most of it.

It's worth remembering where the vocabulary comes from, though. Martin Fowler's 2004 article [Inversion of Control Containers and the Dependency Injection pattern](https://martinfowler.com/articles/injection.html) named both patterns and compared them. He preferred constructor injection too, but his conclusion was more relaxed: "The choice between them is less important than the principle of separating configuration from use."

### What a checked locator removes

For a locator whose dependencies are declared as types:

- **Hidden dependencies.** They're on the class line. `Exporter`'s header says exactly what
  it uses, and you don't open the `.cpp` to find out.
- **Runtime failure on a missing dependency.** A lookup of a type the class didn't declare
  doesn't compile. A declared dependency that the application doesn't compose doesn't
  compile either: `MissingDependency<Aggregator, WorkerPool>`. Runtime failure is impossible.
- **Silent breaking changes.** Adding a dependency is a change to the class line. It shows
  up in the diff, and if a composition doesn't have it, that composition stops compiling.
- **Lying about preconditions.** The precondition is "these components exist and are
  initialized". The type says which ones, and the framework guarantees the rest.

In other words, what made the service locator an anti-pattern was that the dependencies were hidden and unchecked. **We made them declared and checked, most of the argument goes away.**

### What remains

Not all of it. Two things are real.

**The dependency isn't in the constructor.** You can't construct an `Exporter` by hand, pass it fakes, and call it, the way you would with a class that takes `Exporter(Aggregator&, Logger&)`. You test it by composing a smaller application with fakes in it. That's checked like any composition, but it's a different setup.

**Two-phase initialization.** Between construction and `init()`, an object exists but isn't usable. The composition root owns that window, and no code outside it ever sees a half-built component, but the window exists. If a component tries to get a dependency during construction, it will fail in **runtime**; loudly and clearly.

That's the real trade-off. I accept it for components, and only for components. Inside a component, I use constructor injection all the time.

### Why not constructor injection for components?

Because lifecycle is more than construction. Constructor injection orders construction. The order of `start()`, of `stop()`, of `deinit()`, and what happens when the fifth `init()` throws: none of that is in a constructor signature. You'd write it by hand, next to the constructors, and you're back to the beginning of this post.

And something still has to call the constructors in the right order. With a handful of components, that's a few lines in `main()`, and it's fine. Beyond that, you write the order by hand and keep it right forever, or you use a container or framework that derives it. A container is where the magic comes back: bindings, scopes, a separate configuration language for the graph.

Here are the same three components, wired three ways. First, constructor injection, the graph built by a member-initializer list:

```cpp
struct Daemon {
    Config config;
    Logger logger{config};
    WorkerPool pool{config, logger};  // its destructor logs
};
```

Swap the last two lines, and `pool` binds a reference to a `Logger` that isn't constructed yet. On the way down, the logger is destroyed first, and the pool's destructor logs through it. It compiles, and Clang doesn't warn, even with `-Wall -Wextra`. Second, the hand-ordered list from above: swap two `deinit()` calls, same result. Third, keel:

```cpp
class Config : public keel::Component<> { /* ... */ };
class Logger : public keel::Component<Config> { /* ... */ };
class WorkerPool : public keel::Component<Config, Logger> { /* ... */ };

using Daemon = keel::App<WorkerPool, Logger, Config>;  // any order
```

There's no order to swap. The first two versions check the types of the wiring: you can't pass a `Config` where a `Logger` is expected. Neither checks the order. The third doesn't have one to check because it derives it.

### Where this sits

C++ has prior art in this space, so let me try to place keel among it honestly. A short comparison, by what each one does about the problem in this post.

| | Dependencies declared | Wiring mistakes found | Lifetimes owned by | Init and shutdown order |
|---|---|---|---|---|
| Hand-wired `main()` (Pure DI) | constructor signatures | types at compile time; order never | `main()` | by hand, the order of the lines |
| [Fruit](https://github.com/google/fruit) | constructor signatures, plus bindings | mostly at compile time; a few when the injector is created | the injector | construction follows the graph; no start or stop |
| [Boost.DI](https://github.com/boost-ext/di) | constructor signatures, plus bindings | at compile time | the injector or the caller, by scope | construction follows the graph; no start or stop |
| [Chromium `KeyedService`](https://chromium.googlesource.com/chromium/src/+/HEAD/components/keyed_service/README.md) | `DependsOn()` in each factory | at runtime; a missing `DependsOn()` mostly not at all | the factories, one service per context | eager services created in dependency order, others lazily; two-phase shutdown in reverse order |
| [Unreal Engine subsystems](https://dev.epicgames.com/documentation/en-us/unreal-engine/programming-subsystems-in-unreal-engine) | `InitializeDependency<T>()` inside `Initialize()` | at runtime; a cycle not at all | the owner (engine, game instance, ...) | `Initialize()` after its requested dependencies; `Deinitialize()` order unspecified |
| keel | `keel::Component<...>` on the class line | at compile time | the `App` | derived from the graph, for all four phases, with rollback |

Fruit and Boost.DI are good libraries, and they solve a different problem: building object graphs, fine-grained, from constructor signatures. KeyedService and Unreal's subsystems are closer in spirit, coarse services with a lifecycle and an owner, but they're part of their codebases, not something easy to pick up and use in your own `main()`.

Outside C++, this is a solved problem, mostly at the framework level. Go's [fx](https://pkg.go.dev/go.uber.org/fx) runs `OnStart` hooks "in dependency order" and, on shutdown, "the order is reversed". Erlang/OTP's [supervisors](https://www.erlang.org/doc/system/sup_princ.html) start children in the order of their specification and terminate them in reverse. systemd does it for whole processes. The idea is old. What C++ adds is the chance to check it before the program runs.

That's also why I don't call keel a DI framework. "DI framework" brings along things some people distrust. Magic wiring - keel has a little of it (a lookup by type). Runtime surprises, not in keel. Containers that own your objects in ways you can't see - keel has a simple explicit list, no secrets. keel's main job is the part DI frameworks are least known for, **lifecycle and composition, not a DI framework.**

## What the Compiler Still Can't Check

Start with the components that have no edge between them. Their relative order is the list order, which is deterministic, but it isn't something you declared, and a reviewer can't see that the code relies on it. If the order matters, write the edge; that's what `After<T>` is for. Which brings up the one edge the compiler can't catch you leaving out. A missing use doesn't compile, because you call `getComponent` on it. A missing `After<T>` compiles fine, because there is nothing to call.

Then there's what happens inside the hooks. keel guarantees that `Config` is initialized before `Logger::init()` runs. It can't check that the logger actually reads its level from it, or that a component that throws cleans up its partial work first. Threads are the sharpest case of this. The graph orders the hooks, not the threads you start in them. If the worker pool's `stop()` returns without joining, its threads keep running into the `deinit()`s of everything below. keel calls `stop()` at the right time. Making `stop()` actually stop is still your job.

Finally, everything here assumes the set of components is known at compile time. Real applications often pick an implementation at runtime, from configuration. keel provides tooling for that, which we will see in a later post, but runtime choices cannot be checked by the compiler.

## Conclusion

The order an application starts and stops in is not something to maintain. It's a property of the dependency graph, and a hand-written order is a copy of that graph. Worse, it's four copies: construction, init, start and shutdown, kept in different places, and nothing checks that they agree. Copies drift, and the shutdown copy drifts quietly.

Once every component declares what it needs as types, the graph is in the code, and the order is a sort the compiler can compute. A cycle stops being a hang or a crash at startup and becomes a compile error that names only the components on it. Splitting each component's life into resources (`init()`/`deinit()`) and activity (`start()`/`stop()`) means nothing runs while something is half set up, nothing is released while something still runs, and a failed startup rolls back to nothing. And because not every edge is a use, keel has three words for three promises: a dependency, an `Optional<T>`, and an `After<T>`.

Yes, this is a service locator. But what made the service locator an anti-pattern was that its dependencies were hidden and unchecked. Declare them and check them, and most of the argument goes away. What remains is two-phase initialization and testing by composition, and for coarse components with a lifecycle, I think that's the right trade.

So far every component in `telemetryd` has been a concrete class, and every one of them always runs. Real applications depend on interfaces, swap implementations for tests, and let configuration decide what runs. That's where the next post goes.

The complete example for this post is on [Compiler Explorer](https://godbolt.org/) <!-- TODO: short link -->. Run it with `--offline` to see a rollback, or with `-DMISTAKE=1` in the compiler flags to see the cycle. Then move things around in the composition list and watch the order not change.

Write the edges down. Let the compiler do the sorting.
