---
title: LinkedTags - in-sync duplication
id: linked_tags
date: 2023-03-09
tags:
 - SW Engineering
enable_comments: true
---

## The Problem

I have worked with a fair amount of large and complex codebases of varying standards and quality. And, even with good software engineering practices (e.g., [Docs as Code](https://www.writethedocs.org/guide/docs-as-code/)), some level of information duplication is unavoidable. Especially for production-level projects, there may be a huge amount of files and other info linked to a single small piece of code; design docs, requirements, APIs, API docs, user guides, tutorials, safety docs, etc.

Sure, some of these are often unnecessary and the best thing to do would be to get rid of them; but, that is not always an option. For some safety-critical applications such as Autonomous Vehicles, for example, the long list of mandatory docs is not optional.

**This project aims to make the duplication of information throughout a project more manageable and less error-prone. It provides a way of linking places of the codebase that should change together or, at least, be reviewed together.**

In extreme cases, there is often a checklist for the code review. Some items can be automated, some errors can be caught by automated tests, and some checks are done manually.

> For changes to element ABC's interface:
> 1. Update API docs at `src/ABC/API/docs.md`.
> 2. Ensure there are associated requirement links at `plc_docs/ABC/reqs.yaml`.
> 3. If needed, update the sample app at `samples/ABC/` and tutorials at `tutorials/ABC/`.
> 4. ...

This is of course an error-prone process where the reviewer has the burden of checking these. Even the checklist itself must be maintained and may not be accurate. If some of those are missed by the change author, the related file may not even be added to the reviewed change log.

## LinkedTags: The Solution(ish)

LinkedTags allows the developer to add links within the codebase and define policies for each link. For example, consider a code file that defines CLI parameters for an application and another user guide file that documents such parameters. LinkedTags could link the code block that defines the parameters to the associated documentation section.

```python
# @ my_app.py
...
parser = argparse.ArgumentParser()
# @linked_tag{cli_args:span_begin}
# Please update all related links of id `cli_args`
parser.add_argument("arg1", help="arg1 description")
parser.add_argument("arg2", help="arg2 description")
# @linked_tag{cli_args:span_end}
args = parser.parse_args()
```

```md
<!-- @ user_guide.md -->
...
Supported CLI parameters:
<!-- @linked_tag{cli_args:span_begin} -->
* arg1 - arg1 description
* arg2 - arg2 description
<!-- @linked_tag{cli_args:span_end} -->
```

The policy could be defined, for example, as both linked sections shall be changed in the same git commit. Then,
* The tool can be used to automatically enforce the policy within an automated test.
* The development workflow is simplified and more robust. Upon seeing a link tag, right there in the code, the developer now knows that other places in the codebase may also need to be updated - `Ctrl+Shift+F {cli_args}`.

I am not advocating for someone to go out and add these tags all over the place. Excessive usage would probably add too much noise, and excessive tests could degrade the dev experience. However, at the right amount, LinkedTags could make a codebase more maintainable, ensure documentation is (more) appropriately updated, and ultimately improve the development workflow.

Looking forward to getting some feedback on this tool! Let me know if you have any questions, or need any help using it.