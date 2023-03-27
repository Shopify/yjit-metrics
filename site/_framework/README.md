# yjit-metrics static site microframework

So, funny story about Jekyll and Liquid. I initially chose them because GitHub actions defaults to them, and they're not hard to use. Mostly.

But Jekyll as been painful. It's hard to reuse files, because the same file can only be included or never-included. You can't ever sometimes-include something.

And the error messages when you use variables as part of your include file are ***really*** cryptic, and don't include things like line numbers, or the file it's trying and failing to find.

And it's surprisingly hard to turn a directory of files into a directory of HTML ***more than once***. If you have a _benchmarks directory as a collection, you can't easily have five different HTML pages for each element. You can have ***one***. Or copy your files five times. That works too, but is horrible.

And Jekyll doesn't allow symlinks from _include to outside of your repo. So it's hard to put together, let's say, a data dir, a generated-reports dir and a Jekyll source dir into a single HTML repo. Which is what I'm doing here. In fact, Jekyll doesn't allow symlinks ***at all***. And I don't really want to copy over 5GB of reports into a new local dir every time I build the site.

As far as using GitHub Pages for this... turns out there's a 10-minute build time max on GHPages, and sometimes the builds are just randomly slow. So they get unreliable, and you have to go check whether they succeeded or not. Which is ***really*** annoying, given that I'm already running Jekyll myself every time and it's ***much*** faster than that. So I've already done the work, and then GitHub may or may not be willing to replicate it.

All of this adds up to "Jekyll is really bad for my use case." I could adopt Middleman, which is based on Erb. But Middleman recently had a ***multi-year gap*** in their release history, apparently when they just took awhile to decide if they were going to bother any more.

So, um, right, that seems like a bad idea too.

To add insult to injury, there are (as I write this) about six pages of actual MD files, plus two layouts. Not a ton. The amount of actually Jekyll code is ***tiny***.

So: microframework time. That's annoying. Maybe at some point I'll bite the bullet and switch to Middleman or something. But this is a great example of a case where it's not that hard to do it in Ruby, and the existing frameworks for it are all pretty bad for one reason or another.
