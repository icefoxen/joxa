Gonna try to make this runnable on modern systems.  Currently it is not.

After some cosmetic Rebar fixes, it does not run:

```
$ rebar3 compile
===> Verifying dependencies...
===> Analyzing applications...
===> Compiling joxa
make: Circular ~/my.src/joxa/ebin/joxa-compiler.beam <- ~/my.src/joxa/ebin/joxa-compiler.beam dependency dropped.
/usr/lib/erlang/erts-12.2.1/bin/erl -noshell  -pa ~/my.src/joxa/ebin -pa ~/my.src/joxa/.eunit -s 'joxa-compiler' main -extra -o ~/my.src/joxa/ebin ~/my.src/joxa/src/joxa-compiler.jxa
{"init terminating in do_boot",{undef,[{'joxa-compiler',main,[],[]},{init,start_em,1,[]},{init,do_boot,3,[]}]}}
init terminating in do_boot ({undef,[{joxa-compiler,main,[],[]},{init,start_em,1,[]},{init,do_boot,3,[]}]})

Crash dump is being written to: erl_crash.dump...done
make: *** [~/my.src/joxa/build-support/core-build.mkf:79: ~/my.src/joxa/ebin/joxa-compiler.beam] Error 1
===> Hook for compile failed!
```

Not sure whether that circular reference matters, but that error is not printed out when I just try to run the command by hand:

```
$ erl -pa ~/my.src/joxa/ebin -pa ~/my.src/joxa/.eunit -s 'joxa-compiler' main -extra -o ~/my.src/joxa/ebin ~/my.src/joxa/src/joxa-compiler.jxa
{"init terminating in do_boot",{undef,[{'joxa-compiler',main,[],[]},{init,start_em,1,[]},{init,do_boot,3,[]}]}}
init terminating in do_boot ({undef,[{joxa-compiler,main,[],[]},{init,start_em,1,[]},{init,do_boot,3,[]}]})

Crash dump is being written to: erl_crash.dump...done
```

It looks like the compiler is bootstrapped, so no plain erlang code exists anymore outside of tests, and the bootstrap compiler is provided as Erlang syntax trees in `src/ast/*`.  Something is just wrong in those ast files; either the format has changed, or the compiler invocation is missing something 'cause it seems like it can't find the `joxa-compiler` module in the first place.

Looks like the last version of Erlang that this was tested with was Erlang/OTP 21:

```
commit 8a8594e9c81737be4c81af5a4a8d628211f2f510
Merge: 8798558 6c5730d
Author: Eric Merritt <ericbmerritt@gmail.com>
Date:   Wed Mar 6 10:42:43 2019 -0800

    Merge pull request #89 from hhkbp2/fix_comp_erl21
    
    Fix compilation breaks for Erlang/OTP 21
```

So if the author has all the bootstrap-y state checked into the repo correctly, we shoooould be able to install Erlang/OTP 21 and get a working version of this, then maybe roll forward one version at a time.  Looking at previous compilation breaks and their fixes may be enlightening as well?  ...ok not really.

Renaming `rebar.config` to `rebar3.config` gets some different behavior out of rebar3, but not especially promising ones.

Ok when I build it with OG `rebar` instead of `rebar3` it seems to work better, so that needs to be fixed.  It *appears* to build *something* and the unit tests seem to run.  But when I do `make escript` and then run the `joxa` escript it outputs, it doesn't seem to have things like + and -.  Not sure if those have to be imported from the `joxa-core` namespace; the docs say `(joxa-core/!= 1 2)` should work, but it doesn't seem to.  Maybe I have to import something?  Does that work from the CLI?

Running `./joxa reboot_tests/fibonacci.joxa` appears to work, it outputs a `fibonacci.beam` file that we can load and run with the `erl` repl.  `c(fibonacci). fibonacci:fibo(10).` gives correct results.  The `sieve-of-eratosthenes.joxa` file however gives errors:

```
reboot_tests/sieve-of-eratosthenes.joxa:3:9 *error* invalid use declaration: bad namespace name 'joxa.core'
reboot_tests/sieve-of-eratosthenes.joxa:11:34 *error* invalid reference 'rem'/2
reboot_tests/sieve-of-eratosthenes.joxa:11:30 *error* invalid reference '!='/2
reboot_tests/sieve-of-eratosthenes.joxa:12:15 *error* invalid reference '+'/2
```

Ah ok it looks like the `fibonacci.joxa` file doesn't use `joxa.core`, it uses the `erlang` module.  So we can run `(use (erlang :only (-/2 +/2)))` in the repl and then `(+ 3 4)` works.  So it's just not finding the `joxa.core` lib.  Indeed, in the CLI we can do:

```
(use (erlang :only (>/2 -/2 +/2)))
(+ 3 4)
```

and we get 7 out of it.  Huzzah, it works!  So it's not finding its stdlib. All the `make test` invocations look something like this:

```
/usr/local/bin/erl -noshell  -pa ~/my.src/joxa/deps/cf/ebin  -pa ~/my.src/joxa/deps/cucumberl/ebin  -pa ~/my.src/joxa/deps/erlware_commons/ebin  -pa ~/my.src/joxa/deps/getopt/ebin  -pa ~/my.src/joxa/deps/proper/ebin -pa ~/my.src/joxa/ebin -pa ~/my.src/joxa/.eunit -s 'joxa-compiler' main -extra -o ~/my.src/joxa/.eunit ~/my.src/joxa/test/joxa-test-joxification.jxa
```

so maybe we need to give it a lib path somewhere on the command line?

...well there doesn't seem to be a `joxa.core` lib but there's a file called `joxa-core` that declares a namespace with the same name, so if we rename the import in the `sieve-of-eratosthenes.joxa` file to that, does it work?  ...well, we get a different error:

```
reboot_tests/sieve-of-eratosthenes.joxa:3:9 *error* invalid use clause [[quote,as],core,[quote,only],[{'--fun','!=',2}]]
reboot_tests/sieve-of-eratosthenes.joxa:11:30 *error* invalid reference '!='/2
```

So, best case, the docs are wrong.  Reassuring.  ...Ok yes, removing the `:as core` portion from the `ns` block gets us a `beam` file that contains the function we want.  Huzzah!  It...  uh, doesn't look like it *works* correctly, but idk, I'm not really a prime number guy.

Ok it's a bit easier than it looks at first though:

```
joxa-is> (use (erlang))
ok
joxa-is> (erlang/+ 1 2)
3
joxa-is> (use (joxa-core))
ok
joxa-is> (joxa-core/+ 1 2 3)
```

# Language improvements

Or at least, I think they're improvements.  These are just notes of things that stand out at me.

* The `ns` module decl at the start of each file feels overcomplicated.
* I respect needing to explicitly include the stdlib, esp. for a language that appears designed for embedding... but I don't like or want it.
* `defn` for private and `defn+` for public functions feels worse than just `def` and `defp`.  Call me Elixir-brained.
* Not being able to have `>=` and `<=` functions for `gte` and `lte` feels like a skill issue.  Might be a good reason for it?  I'll have to find out.
* ...wait, we have `gte` and `lte` functions but not `gt` and `lt`?  No `not` either?  Wild.
* Currently appears to be a one-pass compiler; you must make forward declarations for mutually recursive functions and structures.
* My soul really needs the basic REPL to include the equivalent of the Erlang `c/1` functions, and readline editing.
* The distinctions between `if/when/unless` don't really spark joy
* Records are as clunky as they are in Erlang (is this a bad thing?)
* Doesn't include Erlang maps (they post-date it)


## Tooling

* Make very, very sure you can bootstrap it and get the correct results out of it before starting to tinker with the bootstrap process.
* Needs updating to rebar3
* Get rid of the makefiles while we're at it
* Not yet sure whether shipping AST files for the bootstrapped compiler is brilliant or bonkers.  BEAM files may be easier?  Or at least not need a shim to load?  Not sure.
* Docs are incomplete and annoying.  The longest section is about how to format the source code.  Need updating.
* Docs use an old version of Sphinx.  Valid, but now would be better to rebuild them using ExDoc.  Not sure how well ExDoc supports random languages though.
* Honestly would be nice if it just compiled to readable Erlang, like Fennel does.  Could we even make an antifennel-like Erlang-to-Joxa compiler?  Maybe!
* Can we do anything with `dialyzer`?  Maybe.  That's a bit of a future subproject.


## Bugs

The REPL seems to need some work:

```
$ ./joxa
Joxa 0.1.0

joxa-is> ($namespace)
'joxa-is'
joxa-is> ($filename)
:0:0 *error* invalid reference '$filename'/0
error
joxa-is> ($namespace)
'joxa-is'
joxa-is> $filename
:0:0 *error* reference does not exist: $filename
error
joxa-is> ($namespace)
error: {error,function_clause} : error: {error,undef} : error: {error,undef} : error: {error,undef} : error: {error,undef} : escript: exception error: undefined function erlang:get_stacktrace/0
  in function  'joxa-shell':loop/2 (/home/NEA.com/simon.heath/my.src/joxa/src/joxa-shell.jxa, line 59)
  in call from 'joxa-shell':start/0 (/home/NEA.com/simon.heath/my.src/joxa/src/joxa-shell.jxa, line 83)
  in call from escript:run/2 (escript.erl, line 750)
  in call from escript:start/1 (escript.erl, line 277)
  in call from init:start_em/1 
  in call from init:do_boot/3 
```

Original readme below:


Joxa
====

__Joxa is a small semantically clean, functional lisp__. It is a
general-purpose language encouraging interactive development and a
functional programming style. Joxa runs on the Erlang Virtual
Machine. Like other Lisps, Joxa treats code as data and has a full
(unhygienic) macro system.

Joxa (pronounced 'jocksah') isn't Erlang, though its very
compatible. Its not Clojure though there is plenty of shared
syntax. It's not Common Lisp though that is the source of the macro
system. While Joxa shares elements of many languages, it is its own
specific language. Although knowing those other languages will
help you get up to speed with Joxa.

Documentation
-------------

More information can be found on the
[Joxa Website](http://www.joxa.org) and the
[Joxa Manual](http://docs.joxa.org). Install instructions are in
INSTALL.md colocated with this Readme. Of course, the canonical source
for all docs and code is the
[github repo](http://github.com/erlware/joxa)
