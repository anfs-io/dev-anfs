A bug report, {{subject}}, was filed in anfs-dev: "{{data.title}}" ({{data.package}}). Read it
with `anfs report show {{subject}}`. Read the AGENTS.md of each repo in your job, and docs'
ROADMAP "For an agent running this list"; follow it. Reproduce the bug minimally through `anfs
work run {{job}} ...` with a temp HOME. If you cannot reproduce it, say so and stop: commit
nothing. Otherwise fix it with a test, run that test file, then the package's suite once, and
commit on the job's branch with {{subject}} in the message. End with a summary: the cause, the
commits, the tests run, and what is left for the person (review, merge, install, `anfs report
close {{subject}} --commit <sha>`).
