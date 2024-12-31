---
title: C++ will be safe one day, but it will be too late
id: safe_cpp_is_dead
date: 2024-12-31
tags:
 - SW Engineering
enable_comments: true
description: C++ will eventually gain safer features, but Rust’s memory safety model is already here; and flourishing. In this article, we explore why C++ might arrive too late to the secure-systems party, despite its vast legacy ecosystem.
---

Over the past few years, C++ has been under pressure from just about everyone concerned with memory safety. The NSA [openly warns](https://www.nsa.gov/Press-Room/Press-Releases-Statements/Press-Release-View/article/3608324/us-and-international-partners-issue-recommendations-to-secure-software-products/#:~:text=Recommended%20memory%20safe%20programming%20languages,integrating%20them%20into%20their%20workflows.) about using C++ while putting it in the same bucket with C as memory-**un**safe languages. Rust, on the other hand, sells itself as memory-safe by default. That’s pretty compelling if your top priority is to avoid the entire category of vulnerabilities tied to manual memory management.

Yet, C++ isn’t going away anytime soon. It has a massive ecosystem of libraries, a decades-long legacy, it is deeply entrenched in every major industry you can think of, and there is a large talent pool for hiring (assuming you are willing to pay enough). Rust, while inherently safer, cannot yet match the breadth and maturity of C++’s ecosystem. That’s the real trade-off right now: Rust is safer from the get-go, but C++ can do just about anything, and has already proven it for decades.

## Where’s the Race?

Rust is improving at a rate that is scary but not surprising. Great tooling, solid documentation, more libraries popping up constantly. Meanwhile, C++ is trying to move toward safer constructs, but it’s hard to introduce the radical needed changes without due diligence. So, the C++ committee moves slowly - real slowly. For some, that’s great (backward compatibility and stability is king). For others, it’s frustrating.

[**Profiles**](https://github.com/BjarneStroustrup/profiles) were supposed to be a solution: “Let’s define a safer subset of C++ so you can opt in to memory safety!” But beyond the general idea, there’s no tangible path forward when focusing on memory safety. That path has not been formally described yet. The committee works by consensus, which is a polite way to say big changes don’t happen overnight. Meanwhile, new projects sometimes skip C++ altogether if memory safety is paramount.

## The Safe C++ Proposal: Blink and You Missed It

The best-known approach to replicating Rust-like guarantees in C++ was [Safe C++ (P3390R0)](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2024/p3390r0.html). It aimed to introduce a Rust-like memory safety model into C++ by enforcing stricter ownership and lifetime rules across codebases. Two core elements of the proposal are the introduction of a superset of C++ with a safe subset (the current Standard Library is full of unsafe APIs) and the introduction of a `safe` specifier – just like the `noexcept` specifier. Unsafe operations would not be allowed in a safe context.

This got shot down almost immediately. Why? The official reasons revolve around compatibility headaches and an unwillingness to fragment the language. Also, it probably felt too drastic for the committee’s evolution-first principles. This is directly tied to EWG's [SD-10](https://isocpp.org/std/standing-documents/sd-10-language-evolution-principles) written by Herb Sutter and just incorporated in the past month. But let’s call it what it is: a big chunk of the community balked at the idea of rewriting large swaths of code just to add safety features. 

> Definition: Viral annotations, one of the reasons listed for rejection of the proposal, refer to changes that propagate throughout an entire codebase.

The same justifications used to reject Safe C++ (fear of breaking code, too big a leap, etc.) haven’t necessarily stopped other disruptive features from being adopted in the past. Think of some of the newer additions, like `consteval` (viral annotations!), concepts, or even modules. Each introduced a fair amount of complexity and change. If they had faced the same level of pushback based on Sutter’s SD-10, we might not have gotten them, either. This raises the question: why is “disruption” acceptable for certain feature sets but not for this particular memory safety proposal? For many in the community, that feels like a double standard, especially when the stakes seem much higher.

I am not claiming that Safe C++ is the correct way to go even though I believe that it points in the right direction. My problem is not with the rejection itself, that was expected. My problem is with the way it got shut down with the wrong justifications, which send a strong and unfortunate message. The reasons given for rejection put C++ in a very awkward spot. What is the path forward for memory-safety? I am not aware of one.

## The Awkward Spot: No Clear Plan

That’s the real dilemma. **The “viral annotations” and safe context approach is the only known strategy that’s worked in a mainstream language (Rust!)**. But in C++, the message from the committee was clear, it’s off the table. Meanwhile, the promise of “profiles” lingers - subsets of C++ that are guaranteed safe. Yet it’s unclear how they’ll handle memory safety without some variation of the similar “viral” and drastic changes proposed in Safe C++.

In other words, **no**. I don’t see a clear path. The folks working on safer C++ might have some ideas, but none have been presented that can realistically match Rust’s guarantees without major upheaval. The committee is not a fan of big upheavals. You do the math.

There may be other feasible and maybe even better paths forward, but those are unknown and we are out of time. It feels like we just shut the door on the most prominent proposal without a backup in sight.

Also put the technical arguments aside and consider the optics of this decision given the large focus and bad press on C++’s memory safety issues. There are a lot of stakeholders watching from the side lines, and it does not look good.

![](/images/posts/safe_cpp_is_dead/tug-of-war.png "'C++ and Rust robotics figures in a tug-of-war while being watched by programmers, managers, and regulators' - DALL-E 3")

## Will Safety Arrive in Time?

If history teaches us anything, it’s that C++ will evolve. It always does, just look at the big changes we’ve seen from C++11 onward. But if you need memory safety right now, you might skip the wait and pick Rust (or something else). Big organizations already are. That’s the rub: C++ might actually get just as safe… in five, ten, maybe twenty years. But by then, Rust could be the default for new safety-critical projects. Or any project; memory-safety pitfalls affect us all.

So, is it “too late” for C++? Maybe not for people already invested in C++ and its unbeatable ecosystem. But for brand-new software, Rust looks more tempting than ever. It’s safe today; no waiting on committees to bless a new feature set. Meanwhile, C++ is still figuring it out. Someday, C++ might have robust safety profiles, but today I feel the least optimistic I have felt about this topic.
