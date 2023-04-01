---
title: Designing a Petri Net Behavior Controller - Example
id: pnet_example
date: 2023-03-03
tags:
 - Behavior
 - Robotics
 - Petri Net
enable_comments: true
---

1. {% post_link pnet_intro %}
2. {% post_link pnet_sw %}
3. ► {% post_link pnet_example %}

---

Following up on my last post {% post_link pnet_sw %}, here is an example of how to model and control a real-world system using a Petri Net-based controller.

![](/images/posts/pnet_example/intro.svg)

> **NOTE**
> * Many details in the use case description are, on purpose, omitted because this example is about high-level behavior control. Things such as which technology is being used to perform each task do not matter for the example.
> * This system could also be optimized, but that is another topic.
> * Transitions are represented by black circles, not rectangles as in previous posts.

## Use Case: Autonomous eCommerce Warehouse

Suppose an eCommerce chain decides to invest in robotics and automate one of its fulfillment centers using Autonomous Mobile Robots (AMRs) and stationary robotic arms. All warehouse bins were adapted so the AMRs can easily pick up, transport, and drop them off autonomously.

The two tasks the system must execute are:

1. **Order execution**. An order is a list of items from the warehouse that must be packaged together.
   1. An AMR must pick up the bins in the warehouse for all the items in the order and take them to a bin-picking station. Each bin contains hundreds of the same item, not only the items requested.
   2. While the AMR awaits, the station will pick up the requested items from the input bins delivered by the AMR and place them in an output bin.
   3. After the bin-picking station is done, the AMR will pick up the input bins it initially delivered and return them to the warehouse.
   4. Another available AMR will pick up the order output bin and deliver it to a packing station.
   5. The packing station will pack all contents of the bin into a single package and send a notification that the order is done.

2. **Replenishment task**. When a warehouse bin is almost empty, this task is issued.
   1. An AMR must pick up the warehouse bin and deliver it to the replenishment center.
   2. While the AMR waits, an operator manually fills the bin with more items.
   3. Once done, the AMR returns the filled bin to the warehouse.

The types of robots added to the system and associated skills are:

* AMRs pick up and drop off bins on warehouse shelves, bin-picking stations, packing stations, and the replenishment center. It can transport multiple bins simultaneously. The available skills are:
    * `transport_bins(pickup_location, dropoff_location, bin_ids)` - the assigned AMR will transport all the specified bins between the specified locations. E.g., pick up three different bins from the warehouse and deliver them to a bin-picking station.
    * `charge(charger_id)` - the AMR will connect to the specified charger until it is fully charged.
    * `is_charged(charge_threshold)` - returns success if the robot battery level is above the threshold.

* Bin-picking stations are composed of a robotic arm with a couple of different end effectors, an input bay where the AMR can autonomously drop off bins, and an output station where empty bins are placed by an operator. The available skills are:
    * `execute_order(order)` - the order is a list of items that must be picked from the input bins and placed in a single output bin.

* Packing stations receive the output bins coming from bin-picking stations and pack all contents of the bin into a single package. The package and the empty bins are not handled by this system. The available skills are:
    * `pack(order_info)` - pack the order.
    * `notify_done(order_info)` - send a notification that the order is done.

Finally, one extra system requirement is that AMRs can only proceed to execute a task if its charge level is above a predefined threshold.

## Modeling the System

My favorite thing about Petri Nets is how easy it is to directly map the model components to single actions or resources. Actions (e.g., `charge robot`) can be directly mapped to places, and resources (e.g., robot, station, order info) can be directly mapped to tokens. A task can then be broken down into a series of sequential actions (places) that the tokens pass through.

> **NOTE**
> This is a good point to stop, take a few minutes to think about the problem, and try to solve it yourself.

The second task is simpler, so probably a good starting point. The task itself can be represented by a token. The task can be broken down into smaller actions that use the available skills. The only needed resource to complete the task is available AMRs.

![](/images/posts/pnet_example/replenishment.svg "Petri Net model of the replenishment task.")

In the same line, the order execution task can be modeled by the following. Note that the bin-picking station ownership is acquired while the robot is still picking up bins in the warehouse because the `transport_bins` skill requires knowledge of the `dropoff_location`. This causes the station to be idle while waiting for the AMR. This could be avoided by breaking up this skill into separate pick-up and drop-off skills.

![](/images/posts/pnet_example/order_execution.svg "Petri Net model of the order execution.")

Finally, the AMR charging requirement must be addressed. Once the AMR is released by one of the branches above, it can only go to the `available AMRs` place if its charge level is above a certain threshold. This is a special case because transitions must be triggered depending on the results of an action.

![](/images/posts/pnet_example/charge.svg "Petri Net model of AMR charging.")

Putting everything together, the full model becomes:

![](/images/posts/pnet_example/full_model.svg "Petri Net full model.")

## From Model to Software

The previous section resulted in a model for the system. Now, the model can be transformed into a behavior controller using the methods described in the previous post: {% post_link pnet_sw %}.

### Tokens

Tokens carry information about each entity(s) it represents on the net. Suppose all skills are executed using, e.g., HTTP requests; the tokens should carry the necessary info for sending the request to the correct location. By representing token data using a generic dictionary-like structure, the following could represent the structure used for all robots.

```json
{
    "{AMR, bin-picking, or packaging}": {
        "id": "...",
        "Addr": "... host ... : ... port ...",
        ... other metadata ...
    }
}
```

For orders:

```json
{
    "order_info": {
        "id": "...",
        "content": [ ... ],
        ... other metadata ...
    }
}
```

Using the logic defined in the previous post for transforming tokens in transitions, the replenishment task branch becomes:

![](/images/posts/pnet_example/replenishment_tokens.svg "Petri Net model of the replenishment task with token transition.")

### Actions

The model makes it trivial to tie places to actions. Since the controller design is intended to be generic and not focused on this use case only, actions could be defined in a configuration file.

```json
{
    {
        "place_id": "ABC",
        "action": {
            "type": "HTTP/POST",
            "address": "... robot host:port ...",
            "path": "/do_ABC",
        }
    },
    {
        "place_id": "DEF" // no action, passive place
    }
}
```

However, note that many of the actions (skills) need token-specific arguments. For example, in the action described by the config above, the HTTP request needs the robot address which is different for each token. One possible technique is to define special string patterns to tell the controller to get that parameter from the associate token. E.g., the pattern `@token{data_key}` means *"get the parameter from the token data at `data_key`"*.

The example above becomes:

```json
{
    "place_id": "ABC",
    "action": {
        "type": "HTTP/POST",
        "address": "@token{AMR/Addr}", // = token["AMR"]["Addr"]
        "path": "",
    }
}
```

The replenishment task branch becomes:

![](/images/posts/pnet_example/replenishment_actions.svg "Petri Net model of the replenishment task with actions.")

### Conditional Transitions

The logic for checking if the AMR is charged is a special case where the action result decides which transition will be triggered. On success (charged), the robot goes directly to the `available AMRs` place; on failure, the robot must be charged first. Of course, this logic could be implemented in a thousand different ways. One way to keep the controller design generic is to add one extra configuration parameter to the transition input arc specifying the acceptable action results for that arc. A transition is then only enabled for tokens associated to the specified results. The example can then be implemented as shown on the left side of the figure below.

> **Note**
> Error handling will be discussed in a future post and is not addressed in this example. However, this section does describe a possible solution for catching and dealing with certain errors and failures. See the right side of the figure.

![](/images/posts/pnet_example/result_filter.svg "Conditional transitions. Charging example on the left, possible error handling on the right.")

## Final Remarks

The example shows how to model a real-world system using a Petri Net, and a few important points for creating a behavior controller from the model. The main points this post aims to convey are:

* Petri Nets are powerful tools for modeling distributed and large systems with many actors operating at the same time. Depending on the scale of the warehouse, hundreds of robots could be controlled at a high level by this single model.

* When done properly, the resulting model is modular and scalable. Adding more robots is as trivial as adding a single token. The two types of tasks modeled share resources, but are completely independent. Changing one should not affect the other. Also, adding a new type of task or process in parallel should be as simple as adding a new branch to the model.

Looking forward to reading your comments and questions! Let me know if you found this article interesting and helpful, and if you would like to read more on similar subjects.
