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

Renaming `rebar.config` to `rebar3.config` gets some different behavior out of rebar3, but not especially promising ones.  It *appears* to build *something* but all the unit tests break.

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
