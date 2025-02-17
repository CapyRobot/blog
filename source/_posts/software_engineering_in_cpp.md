---
title: Programming in C++ is hard, Software Engineering in C++ is even harder
id: software_engineering_in_cpp
date: 2023-06-26
tags:
 - SW Engineering
enable_comments: true
description: It is natural to assume that proficiency in C++ directly translates to the ability to develop software in the language. However, the two are not always synonymous. The complexities of C++ pose challenges for software engineering. Simplicity is important for maintainability and long-term success in software engineering.
---

*Updated on July 6th, 2023.*

There likely is a correlation between one's skill in C++ programming and their ability to develop software in the language. However, these are not the same and do not always evolve together. It is natural to assume that proficiency in C++ directly translates to the ability to develop software in C++. But, the two are not always synonymous. This post discusses how the complexity of C++ creates challenges for software engineering. It also discusses the importance of simplicity for maintainability and long-term success.

Software engineering and programming are not the same.

> "Software engineering can be thought of as 'programming integrated over time.'"

> — Software Engineering at Google


## C++ is Complex, Software Engineering Does Not Like That

C++ is a special case because of its complexity. It provides many ways to accomplish the same thing. And it also carries numerous pitfalls. C++ is such a powerful language, that developers have come up with infinite programming patterns. However, software engineering does not like complexity, and does not naturally get along with C++. Perhaps this is not visible in small projects or teams, but consider the challenges when dozens or even hundreds of engineers work on the same codebase comprising hundreds of thousands of lines.

Just like C, C++ expects the developer to be an expert and to use it with care. Shooting yourself in the foot is quite easy. For large-scale projects with several developers, where not all but only a few will be experts, care and attention **from all involved** are a must.

For example, consider the following software engineering principles.

1. ["You aren't gonna need it" (YAGNI)](https://en.wikipedia.org/wiki/You_aren%27t_gonna_need_it) states a programmer should not add functionality until deemed necessary.

   In C++, this principle can be disobeyed in many different forms. For one, it is tempting to make a function or a class a template so it can be reused for different data types even if it is currently used for a single type. That makes the code harder to read, increases compile time, and degrades the use of tools like linters and code completers. Therefore, this should not be done unless there is a need for it.

2. Avoid Premature Optimization

   This is a well-known principle that can be disobeyed in any programming language. However, if C++ is being used, good performance is likely important to the project. So, some level of optimization is indeed needed. Sometimes, a lot of optimization is needed. The problem is that it is hard to draw boundaries within a project between code that needs to be optimized and code that does not. C++ gives us the tools to optimize everything, and we often optimize more than necessary.

I love C++, and it is my default language of choice. If used properly it will do at least as well as most other languages out there. However, recognizing the language's potential dangers and pitfalls is the first step toward healthy development.

Simplicity is key for good software engineering, and C++ by default is not simple.


## Simplify It When Possible!

The learning journey of C++ often has multiple confidence peaks. The more you learn, the more you realize how much you do not know. And I believe that creates an interesting pattern. Experienced developers tend to limit themselves to subsets of the language and subsets of programming patterns that are sufficient enough and safe. This is an effective approach to simplify the language for easy and **maintainable** development.

I will not provide a recipe for doing that. I am not sure I am qualified to do so. But, one thing that I can say is that simple code is usually better than the most optimal and performant code. In C++, optimal code is often hard to read, hard to understand, and, most importantly, **hard to maintain**.

I would claim that much of C++ programming can be described as **early optimization** on a small scale.

Another problem is that writing complex code can be fun and, sometimes, beautiful. Many developers fall in love with C++ because it enables exactly that. Many of us will find joy when using intricate patterns for the fun of it. However, the problem is that the code often gets more complicated than it needs to be. I, myself, am guilty of this. Developers that fit in this group should at least be aware of what they are doing so they can think twice before overcomplicating things for the fun of it. I have worked with people that fit very well in this group but are not aware of it. Many perceive the addition of unnecessary complexity as a display of skill and fail to see its downsides (or simply do not care).

> "Debugging is twice as hard as writing the code in the first place. Therefore, if you write the code as cleverly as possible, you are, by definition, not smart enough to debug it."

> — Brian Kernighan


## If Simplifying is not Possible, Encapsulate the Complex Bits

If C++ is being used, good performance is likely important to the project. Also, more complex design patterns may be needed or may result in simpler code. In those cases, C++ will provide the right tools for the job, but the resulting code may not be easily legible or easy to understand.

Thankfully, C++ will also provide the tools to properly encapsulate and hide this complexity away. Here, following software engineering principles like [SOLID](https://en.wikipedia.org/wiki/SOLID) with extra attention and care can guide the developer to success.

The extra time needed to properly do this for the complex bits (e.g., deeper design and code reviews) is in the long-term worth it.


## Key Takeaways

1. C++ is known for its vast complexity and offers numerous programming patterns. However, software engineering, which emphasizes simplicity and maintainability, may not readily align with the intricacies of C++.

2. Simplify C++ for maintainable development. Writing code that is easy to understand and maintain is generally more valuable for long-term success than writing code that is optimal and lean.

3. Be aware of overcomplication and early optimization. Hold yourself and your colleagues accountable.

Next time when interviewing someone for a senior C++ role, do not ask the candidate how good in C++ they are, ask them about the pitfalls of C++ for software engineering. It will be very easy to identify engineers with relevant development experience.

Doing the above is easier said than done. Sometimes, complex programming patterns with complex language features will result in simpler and better code. Learning to do it requires not only experience but also awareness. I hope this post will increase your awareness.

I want to emphasize that this post has been written based on my own strong opinions. So, if you agree or if you have a different take, I would love to hear it! Feel free to drop a comment or reach out.
