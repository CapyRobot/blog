---
title: Structuring a C++ Application - `main()` is an architecture decision
id: main-is-an-architecture-decision
date: 2026-11-11
tags:
 - C++
enable_comments: true
description: Why C++ applications grow god classes, and how to structure one instead. Components with a lifecycle, a composition root in main(), and dependencies declared as types that the compiler checks, so the init and shutdown order is derived for you. Introduces keel, a single-header C++20 library built on these ideas.
---

**I never liked wiring an application by hand.**

Every C++ application I've worked on had to answer the same questions: who creates the parts, who wires them together, and in which order they come up and go down. And every time, the answer was written by hand: a constructor that builds everything, a list of `init()` calls, a shutdown sequence that someone once got wrong and patched with a comment.

When I was a researcher in robotics, this happened all the time. Projects started out fine, with a few components and simple dependencies. As they grew, a large, messy application class grew with them.

I remember one bug in particular. Every now and then, a sensor failed to initialize. After a lot of debugging, we found that the shutdown order was wrong: in some edge cases, the sensor handle was not properly released, so the next start couldn't open it. The fix was to reorder two member variables in the application class. A one-line fix, but it exposed the real flaw. What if someone added a member, or moved a few around in a harmless-looking refactor? The design was fragile.

After a few more bugs like that, I started writing a small piece of code that let each part of the application declare what it depends on, and ordered initialization and deinitialization automatically. It never became a real framework. It was a design, simple enough to rewrite on each new project (with a fair amount of copy and paste), and every rewrite improved it a little. I finally put it together in a single header I can carry around, named it keel, and now I'm sharing it with you. These posts describe that design, from the basics to the more advanced parts, roughly in the order it evolved.

Why did I have to write it myself? Because **C++ never settled these questions**, and other ecosystems did years ago. Java has Spring. .NET ships a container in the box. Go has fx, Erlang has OTP supervision trees, and for whole processes there's systemd. C++ has `main()` and good intentions. So every team answers the question again, usually without noticing they're answering it. And the answer most of them drift into is the same: an `Application` class that owns every subsystem, wires them in one constructor, and lets member declaration order decide startup and shutdown. Very often, a god class. I've built a few myself, in teams that knew better.

If you've used dependency injection elsewhere, you know the vocabulary: a composition root, explicit dependencies, a container that orders construction. It doesn't carry over to C++ as-is. Containers in other languages rely on runtime reflection. C++ has DI libraries that work at compile time, but they build object graphs, and starting and stopping an application with threads, sockets and hardware takes more than constructors. And many engineers distrust DI frameworks for valid reasons: magic, failures that only show up at runtime, and complicated error messages.

My design ([keel](https://github.com/mcreduardo/keel)) sits in the middle ground between wiring by hand and a DI framework. Its subject is **the runtime structure of a production C++ application**: components with a lifecycle, one composition root, dependencies declared as types and checked by the compiler, and startup and shutdown order derived from the dependency graph instead of written by hand. This post sets up the problem and the core structure.

If you've lived through a god class, skim sections 1 and 2; the argument starts in section 3.

---

## 1. Every Application Starts as `main()`

Let's use `telemetryd` as an example, a small telemetry agent. It reads samples from a few devices, aggregates them, and exports a summary over the network. Think of the process on a robot, a vehicle or an edge box that ships sensor health to a backend.

Version one is a `main()`, and that's the right call:

```cpp
// telemetryd, version one. Perfectly fine.
int main(int argc, char** argv) {
    const auto settings = loadSettings(argc, argv);
    const auto imu = openDevice(settings.imuPath);
    while (not receivedShutdownSignal()) {
        publish(settings.endpoint, imu.read());
        sleepFor(settings.period);
    }
    return 0;
}
```

Ten lines, readable top to bottom. Order of construction is the order of the lines, destruction is the reverse, and RAII does the rest. Nothing here needs a framework.

Then the requirements arrive, as they do. A second device type. A real config file with reload. A logger with levels, because `printf` doesn't cut it in the field anymore. A worker pool, because reading five devices sequentially is too slow. Aggregation, so we don't ship raw samples. Retries on export.

Six months later `main()` is 600 lines, with lambdas capturing half the stack, and someone says the sensible thing: *"Let's put all of this in an `Application` class."*

**That refactor is the moment the god class becomes a threat.** And it doesn't feel like a mistake. It feels like structure. Everything has a home now.

## 2. Anatomy of a God Class

Here is the `Application` that comes out of that refactor. I have simplified it, but not by much. You have probably seen this class, maybe under a different name.

```cpp
// application.h, the god class.
#include "aggregator.h"
#include "cli_args.h"
#include "config.h"
#include "device_manager.h"
#include "exporter.h"
#include "logger.h"
#include "worker_pool.h"

class Application {
public:
    Application(int argc, char** argv);
    int run();

    // "Temporary" accessors, so subsystems can reach each other.
    Config& config() { return config_; }
    Logger& logger() { return logger_; }
    DeviceManager& devices() { return devices_; }
    WorkerPool& pool() { return pool_; }
    Aggregator& aggregator() { return aggregator_; }

private:
    CliArgs args_;
    Config config_;
    WorkerPool pool_;        // threads; they log
    Logger logger_;          // added later, "next to the other infrastructure"
    DeviceManager devices_;
    Aggregator aggregator_;
    Exporter exporter_;
};
```

```cpp
// application.cpp
Application::Application(int argc, char** argv)
    : args_(argc, argv),
      config_(args_.configPath()),
      pool_(config_.workers()),   // logger_ doesn't exist yet
      logger_(config_.logLevel()),
      devices_(*this),            // takes the whole Application
      aggregator_(*this),
      exporter_(*this) {
    pool_.setLogger(&logger_);    // patched up after the fact
}
```

```cpp
// exporter.cpp
void Exporter::exportOnce() {
    const Snapshot snapshot = app_.aggregator().snapshot();
    app_.logger().info("exporting " + std::to_string(snapshot.size()) + " series");
    send(app_.config().endpoint(), snapshot);
    app_.devices().resetCounters();  // nobody would guess this from exporter.h
}
```

It compiles, runs, and passes code review, because every individual change to it was small and reasonable. Let's look at what it costs.

**1. Hidden dependencies.** What does `Exporter` need? Its header says `Application&`, which means *everything*. To find out, you read `exporter.cpp`, all of it. The call to `resetCounters()` on the device manager is the kind of dependency nobody remembers until it breaks.

**2. Implicit init and teardown order.** C++ constructs members in declaration order and destroys them in reverse. That's a rule every C++ developer should know, but most do not see it when they move a member. Look at `pool_` and `logger_` again. On shutdown, `logger_` is destroyed first. Then `~WorkerPool()` joins its threads, and a thread finishing its last job logs through a logger that no longer exists.

```cpp
    WorkerPool pool_;   // destroyed second: joins threads that still log
    Logger logger_;     // destroyed first
                        // DISASTER: use after destruction, on every shutdown
```

Maybe it crashes. Maybe it prints garbage once a month in the field. Maybe it works for years, until an unrelated change shifts the timing. **The order is load-bearing, and nothing in the code says so.**

**3. Untestable pieces.** To test `Aggregator`, you construct an `Application`. That opens devices, spawns threads and reads a config file. So nobody tests `Aggregator`; they test "the system", slowly, on a machine with the hardware attached.

**4. Compile-time coupling.** `application.h` includes every subsystem, and every subsystem includes `application.h` to reach the others. Touch any header and the world rebuilds. That's annoying, but the real damage is that the *physical* structure now mirrors the logical mess: everything depends on everything.

![](/images/posts/keel_1/god-class-hairball.svg)

**5. Gravity.** Every new feature is one more member, one more accessor, one more line in the constructor. The god class is the path of least resistance, so it keeps winning.

### Why C++ in particular?

Every language has god classes, but C++ makes them especially easy to fall into. Somebody has to own everything. In Java or C#, a DI container owns the objects and wires them. In C++ there is no container by default and ownership is explicit, so ownership and wiring end up in the same place, and that place becomes the god class.

Headers make it worse. Adding `#include "application.h"` costs one line today; the bill (rebuild times, cycles, untestable code) arrives months later, addressed to someone else. And the 90s left us deep hierarchies: an `Application` base class with thirty virtual hooks is a god class by inheritance instead of by membership.

There is a newer reason, too. Coding agents copy the structure they find. Give one a god class and ask for a feature, and you get a bigger god class, very fast.

### Can we fix a god class?

Yes. The issues pointed out above are easy to spot and can be fixed. Split the subsystems out, give each one exactly what it needs (no `Application&`s), and move the wiring to one place. Done carefully, that fix usually ends up as dependency injection by hand: constructors that take their dependencies, and a `main()` that builds everything in the right order and tears it down in reverse. The result can be safe and of good quality.

But it's manual work, and it stays manual. Every new component or dependency means editing the wiring, and keeping the order right is on you for as long as the code lives. **keel was born exactly because I didn't want to do that work when it isn't needed, or maintain it afterwards.**

## 3. What the Literature Gives Us, and What It Doesn't

When I went looking for "how to structure a C++ application", I found two bookshelves that rarely talk to each other.

The C++ shelf works at the level of classes and idioms. Meyers, Sutter, and more recently Klaus Iglberger's [*C++ Software Design*](https://www.oreilly.com/library/view/c-software-design/9781098113155/), which is excellent on managing dependencies between classes with modern C++. But it stops at the class and pattern level. None of the ones I know tells you what `main()` should look like.

The architecture shelf works at the right level: Clean Architecture, Domain-Driven Design, Mark Seemann's work on dependency injection. But it lives in garbage-collected languages with reflection and DI containers, and much of it doesn't translate when you own every byte and every thread.

The closest thing to C++ prior art is John Lakos's *Large-Scale C++ Software Design* (1996). Lakos is serious about dependencies: explicit, acyclic, levelized, and checked by tools. But his subject is *physical* structure, meaning files, libraries, and what includes and links what.

> **Terminology note:** In Lakos's book, a *component* is a `.h`/`.cpp` pair, a unit of
> physical design. In this series, a *component* is a runtime object with state and a
> lifecycle. An application is a composition of components.
> Same discipline (explicit, acyclic, checked dependencies), applied to a
> different graph: who *uses* whom at runtime, instead of who *includes* whom.

C++ has DI libraries too: [Boost.DI](https://github.com/boost-ext/di), Google's [Fruit](https://github.com/google/fruit), [Kangaru](https://github.com/gracicot/kangaru). Some check the object graph at compile time, and they're good at what they do. But they build object graphs; they don't run an application. Startup beyond constructors, activity that starts after everything is ready and stops before anything is torn down, rollback when the fifth subsystem fails to come up: that's left to you. And they're mostly designed for fine-grained injection, while components here are coarse, a few tens per program.

Two more ideas I borrow and want to credit up front:

- The *composition root*, Mark Seemann's term for
  [the single place where an application is wired together](https://blog.ploeh.dk/2011/07/28/CompositionRoot/).
- Decomposition by what's likely to change, from David Parnas's 1972 classic,
  [*On the Criteria to Be Used in Decomposing Systems into Modules*](https://dl.acm.org/doi/10.1145/361598.361623).

The gap, as far as I can tell: **nobody starts from `main()` and builds up to the runtime structure of a production C++ application.** That's what this series tries to do.

## 4. Components: The Unit of Structure

The first idea is to give each subsystem its own class, with a lifecycle, instead of making it a member of something bigger.

> **Definition:** A **component** is an object that lives for the whole application, owns
> some state or resource, has a lifecycle (it is initialized and deinitialized), and
> exists once per application.

In `telemetryd`: the command-line arguments, the config, the logger, the device manager (open device handles), the worker pool (threads), the aggregator (in-memory metrics) and the exporter (a network client). Seven components.

What is not a component: value types, algorithms, per-request or per-sample objects, small helpers. A `Sample` is not a component. A moving-average filter is not a component. Those live *inside* components, as plain C++.

Components are coarse. Rule of thumb: a few tens per application. If you find yourself making a component per class, you are building a DI container by hand, and that's not what we're after.

### Where to draw the boundaries

Three questions get you most of the way:

- Does it own a resource? File handles, sockets, threads, devices, a big cache. Owning
  a resource means it needs an orderly shutdown, which means it needs a lifecycle.
- Does it hide a decision that's likely to change? That's Parnas's criterion. The
  device protocol will change; hide it in `DeviceManager`. The export format will change; hide it in `Exporter`.
- Does the rest of the application need exactly one of it? One logger, one config, one
  pool.

Quick check on `telemetryd`: `WorkerPool` owns threads (yes). `Aggregator` hides the aggregation policy (yes). A `RetryPolicy` struct with three fields? No: that's a value, it goes into `Config` or `Exporter`.

### Two-phase initialization

A component has a constructor and an `init()`, plus the matching `deinit()` and destructor. Why not do everything in the constructor, RAII-style?

Construction only stores arguments, so it's cheap and can't fail. `init()` is where a component acquires its resources and finds its dependencies, and it may throw. What makes the split worth it is that **all components exist before any of them initializes**. A component can look up its dependencies in `init()` without anybody ordering the constructors by hand. The composition root initializes them in dependency order and, if one fails, deinitializes exactly the ones that came up, in reverse.

A member-initializer list gets you part of this: construction in order, destruction in reverse. What it can't express is when activity begins and ends. The exporter must not start sending before everything it reads from is ready, and the worker pool must stop running jobs before the logger it writes to goes away. Components get `start()` and `stop()` hooks for that; this post only needs `init()` and `deinit()`.

This is a known critique of two-phase init, and it's a fair one: there's a window where an object exists but isn't usable. I accept that trade-off for components only, because the composition root owns that window and the code that uses a component never sees it: the root constructs and initializes all components in one call, and dependencies are reachable only from `init()` on. Everything *inside* a component stays plain RAII.

From here on I'll use [keel](https://github.com/mcreduardo/keel), the single header from the introduction. A component derives from `keel::Component<Dependencies...>` and overrides the hooks it needs:

```cpp
// A component. Logger uses Config
class Logger : public keel::Component<Config> {
public:
    void info(const std::string& message) const;

private:
    void init() override { info("logger up, config " + getComponent<Config>().path()); }
    void deinit() noexcept override { info("logger down"); }
};
```

`start()` and `stop()` are optional. Some applications need them, many don't, and this post only uses `init()` and `deinit()`.

## 5. The Composition Root: `main()` Only Wires

The second idea: **one place creates every component, lists them, and owns them all. Nothing else creates components.** That place is the composition root, and it's usually `main()`.

Here is `telemetryd`'s:

```cpp
// The composition root.
using Telemetryd = keel::App<Exporter, Aggregator, WorkerPool, DeviceManager, Logger, Config, CliArgs>;

int main(int argc, char** argv) try {
    return keel::run<Telemetryd>(&Exporter::run, argc, argv);
} catch (const std::exception& e) {
    std::fprintf(stderr, "telemetryd: %s\n", e.what());
    return 1;
}
```

**That's the whole architecture, readable in one screen.** Seven components, one line. `keel::run` constructs them all, initializes them, calls `Exporter::run`, and then deinitializes and destroys everything in reverse, even if something throws halfway through.

Compare that to the god class. The `Application` *knew* about telemetry: its members, its constructor, its accessors were all specific to this program. The owner here is generic. It knows nothing about devices or exporters. The only thing specific to `telemetryd` is a list. From that list and the dependencies each component declares, keel constructs and initializes everything in the right order.

Notice the order of that list. `Exporter` comes first and `CliArgs` last, which is backwards from what has to happen. It doesn't matter: keel computes the init order from the dependencies the components declare, and the run looks like this:

```
[info] logger up, config telemetryd.conf
[info] worker pool up, 2 threads
[info] opened imu0
[info] opened gps0
[info] opened baro0
[info] aggregating 3 devices
[info] export to collector.local:9000: mean=21.000000
[info] export to collector.local:9000: mean=21.000000
[info] export to collector.local:9000: mean=21.000000
[info] closed imu0
[info] closed gps0
[info] closed baro0
[info] worker pool down
[info] logger down
```

The worker pool shuts down before the logger, every time, no matter how anybody reorders anything. The bug from section 2 is gone, and nobody had to be careful: the order is no longer written by hand.

How keel derives that order is the subject of the next post. In this one, the important part is where the order comes *from*: the dependencies. Which brings us to the core idea.

## 6. Dependencies as Types

Components need each other. `Exporter` needs the `Aggregator` and the `Logger`. How does it get to them without `#include "application.h"` and the keys to everything?

The answer: **a component declares its dependencies in its type**, and can reach only those.

```cpp
// Exporter declares what it uses, on the class line.
class Exporter : public keel::Component<Aggregator, Config, CliArgs, Logger> {
public:
    int run() {
        for (int i = 0; i < rounds_; ++i) {
            const double mean = aggregator_->collect();
            logger_->info("export to " + endpoint_ + ": mean=" + std::to_string(mean));
        }
        return 0;
    }

private:
    void init() override {
        aggregator_ = &getComponent<Aggregator>();
        logger_ = &getComponent<Logger>();
        endpoint_ = getComponent<Config>().endpoint();
        rounds_ = getComponent<CliArgs>().rounds();
    }

    Aggregator* aggregator_ = nullptr;
    const Logger* logger_ = nullptr;
    std::string endpoint_;
    int rounds_ = 0;
};
```

Read just the first line: `Exporter` uses `Aggregator`, `Config`, `CliArgs` and `Logger`. That's the complete list, and you didn't open a `.cpp` to learn it.

Inside, `getComponent<T>()` returns the dependency. In `init()`, every declared dependency is already initialized. The pattern is to fetch them once, keep the pointers, and never look them up on a hot path.

Now the part that makes this more than a convention. Let's say someone needs the device names in the exporter and takes the shortcut:

```cpp
    void init() override {
        // ...
        getComponent<DeviceManager>();  // not declared
    }
```

```bash
keel.hpp:548:27: error: static assertion failed due to requirement
'detail::contains<DeviceManager, keel::detail::TypeList<Aggregator, Config, CliArgs, Logger>>':
keel: getComponent<T>() requires T to be listed in this component's keel::Component<...>
telemetryd.cpp:228:9: note: in instantiation of function template specialization
'keel::Component<Aggregator, Config, CliArgs, Logger>::getComponent<DeviceManager>' requested here
```

It doesn't compile. The error names the type you asked for and the list you declared. The only way to use `DeviceManager` from `Exporter` is to add it to the class line, where everybody sees it, including the reviewer.

The same check runs the other way, in the composition root. Remove `WorkerPool` from the list in `main()`, and:

```bash
keel.hpp:804:19: error: static assertion failed due to requirement
'fixed<keel::detail::MissingDependency<Aggregator, WorkerPool>>': keel: missing dependency: the
Component in MissingDependency<Component, Dependency> needs Dependency, and no composed
component is or provides it.
keel.hpp:753:19: note: in instantiation of template class
'keel::detail::MissingDependency<Aggregator, WorkerPool>' requested here
```

`MissingDependency<Aggregator, WorkerPool>`: `Aggregator` needs a `WorkerPool`, and there is none. You find out at compile time, instead of in an edge-case branch that runs once a month in production. (Both outputs are shortened for brevity.)

### What this buys you

You can see what a component needs from its header, and nobody can add a dependency silently: it's a change to the class line, which shows up in the diff and in code review. The application can't be incomplete either, because a missing component is a compile error that names both sides. The graph lives in the types, so tools can extract it and draw it. Coding agents get the same treatment. One that reaches for an undeclared component gets a compile error with the fix in it, so it has to change the declaration, and you see that.

The declarations can stay light, too. The listed types may be forward-declared in the header. You only need the full definition where you call `getComponent<T>()`, typically in the `.cpp`. So declaring dependencies doesn't bring back the include hairball, and the physical structure can stay as clean as the runtime one.

### "Isn't This a Service Locator?"

Yes. `getComponent<T>()` looks things up at runtime, and that has a name: the *service locator*. Mark Seemann famously calls it [an anti-pattern](https://blog.ploeh.dk/2010/02/03/ServiceLocatorisanAnti-Pattern/), and his main argument is that a service locator hides dependencies: you can't see what a class needs from its API, and a missing one fails at runtime.

Not the case here. The dependencies are in the class declaration. Using an undeclared one doesn't compile. A missing one doesn't compile. **The objection is about hidden, unchecked dependencies, and these are neither.** It's a locator whose list is declared and checked.

There is more to that debate (constructor injection, DI containers, what Seemann gets right), but I don't want to fight the whole battle here.

### Why Not Constructor Injection?

The usual alternative is to pass dependencies to the constructor: `Exporter(Aggregator&, Config&, Logger&)`. It's a good pattern for ordinary classes, and inside components I use it all the time. For components, it falls short in two ways.

- A lifecycle is more than construction. Components need `init`, `start`, `stop` and
  `deinit` in a consistent order, with rollback on failure. Constructor injection only orders construction.
- Something has to call the constructors in the right order. You can write that order
  by hand in `main()`, and with a few components it can be perfectly clean. But it's code you don't need: the order is already implied by the dependencies, and a hand-written copy is one more thing to keep in sync. Every new component or dependency means editing it, and when someone gets it wrong, it still compiles. keel derives the order from the declarations instead, so it can't drift.

## 7. You Don't Need a Framework for This

You can apply all of this without keel, or any other library. For years I rewrote the core on every project instead of reusing it.

My first plan was to show a do-it-yourself implementation here. But this post is for engineers at different levels, and many of you already know how to get this behavior just from the examples above. The whole trick is one `static_assert` with a fold expression over the declared dependencies:

```cpp
template <class... Dependencies>
class Component : public ComponentBase {
protected:
    template <class T>
    T& getComponent() const {
        static_assert((std::is_same_v<T, Dependencies> || ...),
                      "T is not listed in this component's Component<...>");
        return static_cast<T&>(*lookup(typeid(T)));
    }
};
```

Everything else is bookkeeping: a registry of components by type, `init()` in order, `deinit()` in reverse, and undoing what was done when an `init()` fails.

If you'd rather see all of it, read [keel](https://github.com/mcreduardo/keel). It is one header, and simple enough to read. Copy the pieces you want; the MIT license lets you.

One warning if you build your own. The easy version keeps the order of the lines. Put the logger below the worker pool, and the pool initializes before the logger it uses; on shutdown the logger goes first, while the pool's threads still log. Nothing notices. That's the bug from section 2, rebuilt in a cleaner-looking codebase. **The order is a graph, not a list.**

## 8. `telemetryd`, Before and After

Put the two versions side by side.

**Before: the god class.**

- `application.h` includes every subsystem, and subsystems includes `application.h`.
- What a subsystem needs may be only in its `.cpp`, spread across calls to `app_.something()`.
- The order of startup and shutdown is the order of the member declarations, plus a `setLogger` call to patch up the one that was wrong.
- Testing `Aggregator` means building the whole application.

**After: components.**

- One header per component, with its dependencies on the class line.
- `main()` is one list, in any order.
- Startup and shutdown order are derived; reordering can't break them.
- An undeclared use, or a missing component, doesn't compile.

And this is the dependency graph of `telemetryd`, which you can now read straight from the class declarations:

![](/images/posts/keel_1/telemetryd-graph.svg)

A few things became easy that weren't before:

- "Who uses the `Logger`?" Grep for `Logger` on class lines. Or ask the compiler: remove
  it from the composition, and every user is named in an error.
- Adding a component is a new class with its dependencies on line one, plus one name in
  the composition root. No constructor to edit, no accessor to add.
- Testing `Aggregator` means composing a smaller application: `Aggregator`, plus fake
  devices and a small worker pool. The composition is checked like any other.

## 9. When Not to Do This

Structure has a cost. Here's when I wouldn't pay it.

- Small tools and scripts.
- Libraries. A library doesn't own the application, so it shouldn't impose an
  application model on its users.
- Fine-grained objects and hot paths. Components are coarse. Don't make every class a
  component, and don't call `getComponent` per sample. Resolve dependencies once in `init()` and keep the pointer.
- When you already have a framework that owns the application. Qt, Unreal and friends have
  their own models of objects and lifetimes.

## 10. Key Takeaways

1. **The god class is a structure problem, not a discipline problem.** It wins because
   ownership, wiring and behavior all end up in one place. Experience alone doesn't prevent it.
2. **Components** give each subsystem its own class and lifecycle. Keep them coarse: a few
   tens per application, plain C++ inside.
3. **The composition root** is the one place that lists and owns them. Ideally, `main()`
   is the architecture, readable in one screen.
4. **Dependencies as types** put each component's needs on its class line, where the
   compiler checks them and reviewers see them. A service locator with declared, checked dependencies doesn't hide anything.
5. **The order is a graph, not a list.** Writing it by hand is the bug from section 2,
   waiting to happen.

You can build all of this yourself. But I've already done it for you, with what the core leaves out: the composition checked at compile time, the order derived from the graph, and one clear error per mistake. That's [keel](https://github.com/mcreduardo/keel), one header.

The complete `telemetryd` example is on [Compiler Explorer](https://godbolt.org/z/35K3ah1x5). Build and run it in your browser. Try removing a component from the composition, or using one you didn't declare, and read what the compiler tells you.

**Next:** why init order is a graph, and what the compiler can check about it.
