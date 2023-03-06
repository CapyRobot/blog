---
title: What are Petri Nets? Where do they fit in the Robotics Stack?
id: pnet_intro
date: 2023-01-14
tags:
 - behavior
 - robotics
 - petri nets
enable_comments: true
---

1. ► {% post_link pnet_intro %}
2. {% post_link pnet_sw %}
3. {% post_link pnet_example %}

---

![](/images/posts/pnet_intro/intro.svg "Petri Net")

I am frequently asked whether Finite State Machines (FSMs) and Behavior Trees (BTs) should be used to model certain systems. However, the answer is not always clear-cut. Should I use one of them, both of them at different layers, or none? Modern systems often require multiple behavior layers that can be modeled using different languages. While FSMs and BTs are popular choices, there are other options available that may be more suitable depending on the specific use case and system characteristics. In this article, I will introduce Petri Nets, one of my personal favorite modeling languages. Though you may not have heard of it before, Petri Nets are widely used in various applications, sometimes subconsciously or under different names. If you’ve ever used an FSM, you have used a Petri Net, as FSMs are a subset of Petri Nets.

In this article, I will address two key questions.

1. *What are Petri Nets?*
2. *Where do they fit in the Robotics Stack?*

## What are Petri Nets?

A Petri Net is a mathematical modeling language especially suited for the description of distributed systems.

The two main components of a Petri Net are **Places** and **Transitions**, the white circles and black rectangles respectively. Directed arcs connect places to transitions or vice-versa. **Tokens**, the small black circles in the image below, are used to mark the state of the net. They move from Place to Place as Transitions are fired. Each place may contain a discrete number of Tokens, and the overall state of the net (also called a *marking*) can be defined as the distribution of tokens across the places of the net.

![](/images/posts/pnet_intro/net_nomenclature.svg "Petri Net nomenclature.")

A transition can only be fired when it is enabled; all places that point to the transition have at least one token. When a transition fires, an atomic event takes place, consuming one token from each place that points to the transition and producing one token to each place that the transition points to. See the example in the image.

![](/images/posts/pnet_intro/net_firing.svg "Transition firing example.")

Let’s look at some examples and discuss a few interesting techniques.

### Example 1: A simple communication protocol

This is perhaps the most popular example I have seen out there. Consider a simplified communication protocol where the sender sends a message and expects to receive an Ack to confirm that the consumer received the message. The receiver will wait for a message to arrive in its receive buffer and, then, send an Ack back. This behavior is easily modeled with Petri Nets.

![](/images/posts/pnet_intro/net_example_1.svg "Example 1: a simple communication protocol.")

This example shows how Petri Nets can represent multi-agent or asynchronous systems. Representing the same system using a single FSM results in a mostly linear sequence of states, which are not as intuitive. Using a single FSM for this purpose also generates a worse representation of the division of work between sender and receiver.

Note that Petri Nets not only provide a clear representation of the markings that are reachable from the initial marking, but they also make it easy to identify problematic or undesirable states. For example, a marking with only tokens at `Waiting for ack` and `Ready to receive` represents a [deadlock](https://en.wikipedia.org/wiki/Deadlock). This highlights the power of Petri Nets in terms of **observability**. Forbidden or problematic markings could be manually defined or even automatically found using Petri Nets’ well-developed mathematical theory for process analysis, and then detected by an observer software component during execution. Trying to represent the same information in a single FSM would be more complex, as the number of possible states in a system tends to grow exponentially to the number of independent actors.

### Example 2: Resource sharing

Consider two autonomous electric taxis that share the same charging station. The Petri Net below could model the behavior for controlling charger access.

![](/images/posts/pnet_intro/net_example_2.svg "Example 2: resource sharing.")

This example shows the nondeterministic characteristic of Petri Nets. If both taxis are waiting for charging station availability, which transition should be fired? `T1` or `T2`? Unless the model has a defined execution policy, e.g., the transition that was first enabled has higher priority, the model cannot know. But remember, these are distributed and asynchronous systems that are inherently nondeterministic unless such extra policies are defined. The same characteristic would be true if using other modeling languages that also do not enforce such policies.

Another important aspect to consider in this example is scalability. How can we scale up the net defined above? Suppose we want to model multiple vehicles and multiple available charging stations. A naive approach would be to create a branch for each vehicle; similarly to the net above that has two branches for two vehicles (see the left side of the figure below). Sometimes that is a valid solution, but the size of the net increases with the size of the fleet.

Another technique that we could use is to think of agents or entities as tokens that pass through a common execution branch (right side of the figure below).

![](/images/posts/pnet_intro/net_example_2b.svg "Example 2: resource sharing - scalability.")

This is a popular way of modeling systems that require such **scalability**. One disadvantage is that now the model has lost track of which specific taxi is getting into or leaving this branch of the net. If you are using this model for high-level observability, it may not matter. In other instances, however, it might become critical to track the comings and going of each taxi. One obvious way to address this issue is to tie the entity info to the specific token that represents it. That can be achieved using a variant of the language known as Coloured Petri Nets, where tokens can carry values. See the variants section below.

### Example 3: Producer-consumer

This last example, which I am leaving as an exercise to the reader, shows a clever and commonly used pattern. Can you figure out the purpose of the place `PX`? What would happen if it was removed?

![](/images/posts/pnet_intro/net_example_3.svg "Example 3: producer-consumer.")

## Petri Net Variants

There are numerous variants to this modeling language. Here are a few of the popular ones.

- **Extended Petri Net**: this variant adds the definition of inhibitor arcs. These arcs go from a place to a transition. When such a place is marked, the transition is always disabled.

![](/images/posts/pnet_intro/extended_net.svg "Extended Petri Net.")

- **Finite Capacity Nets**: in this variant, each place has a maximum token carrying capacity. A transition is disabled if it would violate any place’s maximum capacity. Note that this is useful for representing limited capacity more easily, but it adds no functionality to the modeling language. Standard Petri Nets can also enforce capacity as we saw in example 2 when limiting the usage of a resource with limited availability.

- **Coloured Petri Nets**: this variant extends the standard language by allowing the distinction between tokens. I.e., it allows tokens to have values attached to them. See the last paragraph of example 2 for an example of how this could be useful.

![](/images/posts/pnet_intro/coloured_net.svg "Coloured Petri Net.")

## Where do Petri Nets fit in the Robotics Stack?
At this point, you may already have a few good ideas of how to leverage this modeling language.

When it comes to control and behavior, the answer is that this language should be used wherever it is at least as appropriate as the other available modeling languages when considering use case and system characteristics. As already mentioned, Petri Nets do especially well for representing systems that are distributed, asynchronous, dealing with multiple agents, etc. Let us see how that is applied to different levels of the behavior stack.

Modern architectures often split robot control into multiple layers. Consider the classic [3T (three-tiers) architecture](https://home.gwu.edu/~jcmarsh/wiki/pmwiki.php%3Fn=System.3T.html) as an example. It has the *Behavioral layer*, which represents the lowest level of control. It directly deals with sensors and actuators, and it implements the so-called robot behaviors (or skills). The middle man, the *Executive layer*, translates high-level plans into the execution of low-level behaviors implemented by the Behavioral Layer. Finally, the top layer, the *Planning layer*, looks toward the future and is responsible for the high-level and long-term control of the robot. The boundary between these layers can heavily depend on personal preferences or the exact architecture being used.

Asynchronous or concurrent tasks may happen in any of those three layers but are usually more complex towards the top two layers. The Behavioral Control layer has its own challenges, but, since there usually are abstractions on top of sensors and actuators software, those challenges are isolated and rarely propagate to the higher-level robot control elements.

The Planning layer often is the one that communicates with other robots and agents in the environment. Consider a fleet of robots that share multiple resources. The planning layer could check if resources for process A are available, and, if not, opt for executing process B in the meantime. Such logic could be easily implemented using a Petri Net; see example 2 as a hint of how that could be achieved. Sometimes, multiple robots or agents even share the same planning component; perhaps the best and most common use case for using Petri Nets in the behavior stack.

It is fairly rare for Petri Nets to be used at the level of the Executive layer. Behavior Trees (or similar) languages seem to fit better with the paradigm of breaking down a high-level state into a series of sequential or parallel low-level robot behaviors. Sometimes these series of tasks may even be auto-generated or auto-assembled during runtime, which could be challenging if using Petri Nets. Some BT variants can also represent concurrent tasks well.

Finally, Petri Nets could be used for the purposes of observability only and not even be part of the Robot’s control stack.

### Advantages and disadvantages

Petri Nets can make it very intuitive to tie places and tokens to actual components or processes of the system. Then, design patterns (e.g., the resource availability pattern) can be used to represent constraints and desired behaviors. The same is not as easily achievable with FSMs and BTs.

Petri Nets have an exact mathematical definition of their execution semantics, which is useful for easy software implementation and to **make sure your network is healthy**. It is beyond the scope of this article, but there are formal structural and state space analysis techniques that can be used to assess Petri Nets properties, provide important insights into the design, and point out possible issues. For example, one could use such techniques to check if undesired or forbidden markings are reachable, assess the liveness of the model, or check for any possible deadlocks. For more details refer to the Further readings section below.

The main disadvantage of using Petri Nets is definitely its lack of boundaries or constraints, which can result in undesirable complex models. Considering all possible extensions to this language, almost anything is achievable. That is not always a good thing since it is up to the user to be careful. If a system can be adequately modeled by a more constrained language, e.g., FSMs or BTs, then that is preferred. When determining whether to rely on Petri Nets, remember key use cases; distributed systems, concurrent processes, multi-agent control, etc.

## Further readings

[James L. Peterson, Petri Net Theory and the Modeling of Systems, (2019 revision)](http://jklp.org/profession/books/pn/index.html) is probably the most complete reference out there. It has everything from formal definitions, modeling examples, analysis of models, properties, variants, etc.

[Tadao Murata, Petri nets: Properties, analysis, and applications. (1989)](https://inst.eecs.berkeley.edu/~ee249/fa07/discussions/PetriNets-Murata.pdf), a tutorial-review paper, is a more succinct option.

And, of course, [Petri Net (Wikipedia)](https://en.wikipedia.org/wiki/Petri_net#CITEREFPeterson1981) has summaries of many relevant topics and a large list of references.

## References

1. Peterson, James Lyle. Petri net theory and the modeling of systems. Prentice Hall PTR, 1981.
2. Murata, Tadao. “Petri nets: Properties, analysis, and applications.” Proceedings of the IEEE 77.4 (1989): 541–580.
3. Peter Bonasso, R., et al. “Experiences with an architecture for intelligent, reactive agents.” Journal of Experimental & Theoretical Artificial Intelligence 9.2–3 (1997): 237–256.

Looking forward to reading your comments and questions! Let me know if you found this article interesting and helpful, and if you would like to read more on similar subjects.

