---
title: Petri Nets for Robotics - A behavior Controller
id: pnet_sw
date: 2023-02-20
tags:
 - behavior
 - robotics
enable_comments: true
---

![](/images/posts/pnet_sw/intro.svg "Petri Net Controller.")

Translating a Petri Net into software is easy; all an OOP implementation needs are a couple of classes to represent transitions and places, and a basic interface for triggering transitions and querying the current state of the net. But, using a model to actively control the behavior of an actual autonomous system, e.g., a fleet of autonomous robots, is another story.

*Who is responsible for triggering transitions? Should the net software element actively command actions? Or should the net be passive and wait for agents to query the current state and decide what to do by themselves?*

In this article, I will discuss some of the key challenges faced when implementing controllers based on Petri Nets. **My aim is that, after reading this article, the reader should be able to implement their own Petri Net-based behavior controller in a clean, reusable, and maintainable way**. I assume the reader is familiar with Petri Nets. If that is not the case, check out my previous post: {% post_link pnet_intro %}.

## What does this software element do?

Different from the last post, the Petri Net now is more than a mathematical model, it is also an actual software element. Let's start with the most simple possible design.

### A passive implementation

The one thing it must always do is obvious, model a system and keep track of its current state. That is the most simple form of this software element; it has a representation of the model in the format of places, transitions, and tokens, and it provides an interface to query its current state and an interface to trigger transitions.

![](/images/posts/pnet_sw/passive_diagram.svg "A passive implementation.")

In this approach, the decision process is delegated to the users of the element. The net does not decide which transitions to trigger; it is completely passive. If the system is complex enough such as a Petri Net was chosen over simpler modeling languages, it is expected that there are multiple entities (multiple users) being modeled and controlled concurrently. These entities have to do that job themselves and, to do that, they must have some global knowledge of the system. Not only the knowledge coming from the current state of the net but also knowledge about how triggering transitions could affect other entities also in the net. This approach works for some systems, but requiring shared global knowledge of the system can be a huge disadvantage.

Imagine a system with multiple robots and machines collaborating. How many of those entities have to be able to interpret the net and decide if transitions should be fired or not? If one of the machine's behavior changes, how many of the other entities are affected and must be adapted to handle those changes? These questions are not easy to answer. This approach can lead to systems that are not modular and not scalable. Having multiple entities dealing with high-level behavior at the same time could also generate other challenges such as synchronizing access to the net.

### Adding a behavior controller

Another approach is to have a single component to encapsulate this global behavior knowledge, which includes knowing what actions must be executed in each state and how to fire transitions. Let's call this element as the *behavior controller*.

The main advantage of this approach is that it centralizes all high-level behavior control knowledge into a single component. Entities are basically treated as an actor with a known set of supported skills or behaviors. For example, an Autonomous Mobile Robot could provide an API of high-level skills such as `move to landmark` and `go to charging station` that can be called by the behavior controller.

![](/images/posts/pnet_sw/behavior_controller.svg "Behavior controller.")

The controller must look at the net and decide which transition to fire and which actions must be executed. Dealing with transitions is usually where there is the most confusion, so let's save that topic for the next section below. Thankfully, Petri Nets make dealing with actions very simple. Remember that one of the main advantages of using this language is that it can make it very intuitive to tie places and tokens to actual components or processes of the system. For a well-designed model, places and actions can be directly mapped to one another. In fact, many places are named after an action, e.g., `moving from A to B`. This not only facilitates the implementation of the controller component, but it allows for scalable and generic design.

Each place can be tied to a set of actions to be executed when the place is occupied by a token (preferably a single action per place for simplicity). In implementation terms, an action could be represented by a callback function or a service request for example. Each of these actions does not have to be implemented by the controller module and can be delegated to the user; making the implementation generic and not use-case specific. This could be achieved, for example, by using configuration files where a place definition also gives the possibility of specifying associated actions in the form of, e.g., HTTP requests or ROS services.

Here is a simple implementation example for executing actions. 

```c++
// Epoch (to be executed periodically)

for (auto&& place : occupiedPlaces)
{
    if (place.hasAssiciatedAction())
    {
        // For tokens added to the place in this epoch
        for (auto&& token : place.getNewTokens())
        {
            asyncActiveActions.append(
                place.executeActionAsync(token)); // non-blocking call
        }
    }
}
...

for (auto&& finishedActions : asyncActiveActions.getFinishedActions())
{
    // should this action completion trigger a transition?
    // should this action be restarted?
    // to be continued...
}
```

My personal preference is to have an action return one of three possible responses when done `{success, failure, in_progress}`. The `success` and `failure` values are used to decide which transitions should be triggered, and the `in_progress` value is used to retrigger the action in the next epoch. For example, a place that represents robot charging could be associated with the following action.

For each robot in the place (represented by a token), the action calls a `get charging status` service that returns

* `success` when charging is done and the robot token could be moved forward;
* `failure` in case of any errors or unexpected events and the token could be moved to an appropriate `in error / needs assistance` place;
* and `in_progress` if charging is not yet complete and the task should be retriggered at a later time.

## Triggering transitions

This is the topic that usually generates the most confusion and needs some care if it is desired to produce a modular and scalable implementation. 

First, a note on what transitions actually mean. A transition triggering is an [atomic event](https://www.oxfordreference.com/display/10.1093/oi/authority.20110803095432251;jsessionid=D0FD769E95401062B016AB7EDB4172EB) that changes the state of the net; it is instantaneous. So, by this definition, it should never be tied to an action. However, it is a fair idea to tie a transition to conditions like *"arrived at B"*, this will not necessarily hurt the design, but I would advise against it. Translating that into software means some sort of callback function or memory access to assess the condition. Adding this extra complexity is unnecessary because places, as shown in the previous section, are already able to assess conditions using the same mechanisms implemented to execute actions. My personal preference is to leave transitions as simple as they can be; nameless and with no more information than arcs to input and output places.

Now, back to this section's topic. When to trigger one of them?

Considering all nets defined within the boundaries of the modeling language, there is no obvious answer to this question (well, at least I have not found one). So, the solution here presented is based on a couple of new definitions and constraints that a net must follow. However, any given model can be adapted to meet such constraints.

Let's define a special type of transition, **Auto-Triggering (AT) transitions**. These are the ones that should always be instantaneously triggered by the controller once they are enabled. See the robot charging example below.

![](/images/posts/pnet_sw/AT_transition_1.svg "Auto Triggering transitions - charging example.")

Transition `T1` is an AT transition because if it is enabled, there is a robot that needs to charge and a charger that is available, there is no reason to not trigger this transition. Note that the transition is an AT transition because all places that point to the transition are passive places that are not associated with any actions. The resources (tokens) in those places are simply waiting.

Transition `T2` on the other hand in not an AT transition. Even if it is enabled, the controller should not trigger it until the robot is finished charging. The place that points to it, `Charging`, is associated with an action that must finish before releasing a token.

This observation defines the first rule for our controller. 

> Auto-Triggering transitions, transitions in which no input places are associated with actions, should be automatically triggered when enabled.

What does the controller do with other non-AT transitions? As hinted previously, it can wait until the action is completed before triggering the transition. If the transition has a single input place, doing that is very simple; when the action is done, the transition gets immediately triggered. However, things get a bit more complicated when there are multiple input places. In this case, we have no guarantee that the transition is enabled upon action completion.

Let's make the charging example a bit more complex so `T1` is not an AT transition. Now, the place `Moving to charging location` is associated with an action, and the transition must wait for it to complete.

![](/images/posts/pnet_sw/AT_transition_2.svg "Auto Triggering transitions - charging example. Highlighted action.")

Once the robot arrives at the charging location, it cannot simply trigger `T1` because it may not be enabled due to the lack of available chargers. A more complex software implementation can solve this issue. It could add state variables to track which actions (and associated tokens) are completed and use a more complicated logic for trying to trigger such transitions. However, doing so is not trivial since there are some "fun" edge cases that must be dealt with, and doing so and not really needed. 

The following constraint makes sure that such problematic transitions do not exist, and a net can always be easily adapted to obey.

> A non-AT transition shall have no more than a single input place.

If that is the case, all non-auto-triggering transitions can always be fired at the completion of the task, and all transitions that have more than one input place are guaranteed to be auto-triggering transitions. Also, it is very easy to adapt to this rule.

> For any transitions that violate it, the input places of such transitions that are associated to an action shall be split into two: a place associated with an action and a subsequent passive place. 

See how our example is fixed in the image below.

![](/images/posts/pnet_sw/AT_transition_3.svg "Auto Triggering transitions - charging example. Adapted.")

Transition `T1` is now AT, and the new transition `T0` (non-AT) only has a single input place.

My suggestion of modifying the net model to simplify the software implementation probably raised some eyebrows. But, even if the software element complexity was not a factor, I would still advocate for this rule. Following it also improves the model by getting rid of hidden states and making the model more appropriately expressive. If the net were to be used for observability, it makes clear the exact state of each entity (token) being controlled. See the example presented above; the initial place `moving to charging location` could host tokens in two different states.

## Encoding information within a token

In most cases, a token has meaning beyond only keeping track of the state of the net. It can represent a resource, a task, a product, etc. For example, a robot that is executing a process modeled by the net may be represented by a specific token that moves from place to place. Using the same example as before, the controller must differentiate between which robot or charger is doing what. The *Colored Petri Nets* variation allows us to do that exact separation; each token is assigned a specific color that allows the model to keep track of the instances that move within the network.

![](/images/posts/pnet_sw/colored_tokens.svg "Colored tokens - charging example.")

Of course, on the implementation side, we are not tagging tokens with actual color, but we can instead add ids (e.g., `Robot ABC`) or even more complete data structures (e.g., `{"robot": {"id": "ABC", "ip": ...}}`).

One could define specific structures for each type of token or each place, and define conversion functions for each transition, but that would be use-case specific. My personal preference is to use dictionary-like structures, e.g., C++ JSON objects, to make the implementation more generic and reusable. 

Transitions also play a role here; they convert token types. In the example, tokens can be of types `Robot`, `Charger`, or `Robot + Charger`. The first transition consumes two tokens of types `Robot` and `Charger` and produces a token of the type `Robot + Charger`. For dictionary-like structures with format `{"type id": {...}}`, it is simple to apply data transformations using the arcs. The following two rules are sufficient to transform the tokens for this example, and for most use cases.

> The resulting token data in an output place is by default the concatenation of the data of all tokens consumed by the transition.

![](/images/posts/pnet_sw/tokens_merge.svg "Merging tokens example.")

> Each arc has an optional configuration parameter to specify top-level data keys that are allowed to pass through.

![](/images/posts/pnet_sw/tokens_filter.svg "Filtering tokens example.")

The charging example could be adapted as in the figure below.

![](/images/posts/pnet_sw/arc_charger_example.svg "Filtering tokens for the charging example.")

## Final remarks

This article covered the points I believe are the most important ones for implementing a Petri Net-based behavior controller. Of course, it does not cover everything needed, but the points covered here are enough to guide the major architectural decisions related to designing a **clean, reusable, and maintainable** software component. This article could be used as a starting point, but there are still many fun challenges to be solved.

One very important topic that is, on purpose, missing from this article is **error/failure handling**. I chose not to add it here for two reasons. First, in my opinion, this topic is more closely related to modeling than to software implementation since, in practice, most failures and system errors can be handled by the model itself. Second, this topic is extensive enough that I think I would not be able to cover it well in a single section. It warrants another dedicated post.

To recap, the software element could be completely passive; it only tracks the current state and delegates controlling decisions to anybody else using the element's interface. This approach does not usually work well since potentially delegating behavior decisions to multiple entities can get quite complex, not easily maintainable, and flat-out messy. Another approach is to include a behavior controller into this software element to take all high-level behavior decisions and to actively tell all entities what they should be doing. As shown here, this behavior controller could be designed in quite a generic and reusable way.

The wording high-level was used many times throughout the article. The behavior controller is said to deal with high-level behavior decisions because if a system is complex enough to justify the use of a Petri Net, the behavior architecture is likely to be split into multiple layers. The Petri Net is usually responsible for the most high-level layer. Other lower-level control layers more commonly use behavior-tree-like modeling languages. {% post_link pnet_intro 'See my previous post on Petri Nets' %} for more context on this topic.

I will follow up in my next post with a realistic example of modeling a real system with a Petri Net following the rules laid out here, and with a few useful modeling patterns.

Looking forward to reading your comments and questions! Let me know if you found this article interesting and helpful, and if you would like to read more on similar subjects.
