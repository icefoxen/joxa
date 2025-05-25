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

Ok but building the thing with `rebar` and OTP/24 fails:

```
make[1]: Entering directory '/home/NEA.com/simon.heath/my.src/joxa'
/usr/bin/erl -noshell  -pa /home/NEA.com/simon.heath/my.src/joxa/deps/cf/ebin  -pa /home/NEA.com/simon.heath/my.src/joxa/deps/cucumberl/ebin  -pa /home/NEA.com/simon.heath/my.src/joxa/deps/erlware_commons/ebin  -pa /home/NEA.com/simon.heath/my.src/joxa/deps/getopt/ebin  -pa /home/NEA.com/simon.heath/my.src/joxa/deps/proper/ebin -pa /home/NEA.com/simon.heath/my.src/joxa/ebin -pa /home/NEA.com/simon.heath/my.src/joxa/.eunit -s 'joxa-compiler' main -extra -o /home/NEA.com/simon.heath/my.src/joxa/ebin /home/NEA.com/simon.heath/my.src/joxa/src/joxa-core.jxa
{"init terminating in do_boot",{badarg,[{erlang,element,[1,[quasiquote,[{'--fun',erlang,'=/='},[unquote,a1],[unquote,a2]]]],[{error_info,#{module=>erl_erts_errors}}]},{'joxa-cmp-expr','make-expr',3,[{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-expr.jxa"},{line,359}]},{'joxa-cmp-expr','do-function-body',6,[{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-expr.jxa"},{line,280}]},{'joxa-cmp-defs','make-function1',5,[{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-defs.jxa"},{line,17}]},{'joxa-cmp-defs','make-definition',3,[{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-defs.jxa"},{line,53}]},{'joxa-compiler','internal-forms',2,[{file,"/Users/emerrit/workspace/joxa/src/joxa-compiler.jxa"},{line,312}]},{'joxa-compiler',forms,3,[{file,"/Users/emerrit/workspace/joxa/src/joxa-compiler.jxa"},{line,322}]},{'joxa-compiler','do-compile',2,[{file,"/Users/emerrit/workspace/joxa/src/joxa-compiler.jxa"},{line,573}]}]}}
init terminating in do_boot ({badarg,[{erlang,element,[1,[_]],[{_}]},{joxa-cmp-expr,make-expr,3,[{_},{_}]},{joxa-cmp-expr,do-function-body,6,[{_},{_}]},{joxa-cmp-defs,make-function1,5,[{_},{_}]},{joxa-cmp-defs,make-definition,3,[{_},{_}]},{joxa-compiler,internal-forms,2,[{_},{_}]},{joxa-compiler,forms,3,[{_},{_}]},{joxa-compiler,do-compile,2,[{_},{_}]}]})

Crash dump is being written to: erl_crash.dump...done
```

uhhhh let's take that apart some:

```erlang
{"init terminating in do_boot",
  {badarg,
    [
      {erlang,element,
        [1,
          [quasiquote,[{'--fun',erlang,'=/='},[unquote,a1],[unquote,a2]]]],
        [{error_info,#{module=>erl_erts_errors}}]},
      {'joxa-cmp-expr','make-expr',3, [{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-expr.jxa"},{line,359}]},
      {'joxa-cmp-expr','do-function-body',6,[{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-expr.jxa"},{line,280}]},
      {'joxa-cmp-defs','make-function1',5,[{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-defs.jxa"},{line,17}]},
      {'joxa-cmp-defs','make-definition',3,[{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-defs.jxa"},{line,53}]},
      {'joxa-compiler','internal-forms',2,[{file,"/Users/emerrit/workspace/joxa/src/joxa-compiler.jxa"},{line,312}]},
      {'joxa-compiler',forms,3,[{file,"/Users/emerrit/workspace/joxa/src/joxa-compiler.jxa"},{line,322}]},
      {'joxa-compiler','do-compile',2,[{file,"/Users/emerrit/workspace/joxa/src/joxa-compiler.jxa"},{line,573}]}
    ]
  }
}
{badarg,
  [
    {erlang,element,[1,[_]],[{_}]},
    {joxa-cmp-expr,make-expr,3,[{_},{_}]},
    {joxa-cmp-expr,do-function-body,6,[{_},{_}]},
    {joxa-cmp-defs,make-function1,5,[{_},{_}]},
    {joxa-cmp-defs,make-definition,3,[{_},{_}]},
    {joxa-compiler,internal-forms,2,[{_},{_}]},
    {joxa-compiler,forms,3,[{_},{_}]},
    {joxa-compiler,do-compile,2,[{_},{_}]}
  ]
}
```

...Oh thank Eris it's an actual stack trace, something handed something bad to `erlang:element`.

## Next sprint

When I do `make test` with OTP 27 and rebar2 then it mostly appears to work up to a point, but then I get:

```
make[1]: Entering directory '/home/icefox/my.src/srht/icefox/joxa'
/usr/bin/erl -noshell -pa /home/icefox/my.src/srht/icefox/joxa/ebin  -pa /home/icefox/my.src/srht/icefox/joxa/deps/cf/ebin  -pa /home/icefox/my.src/srht/icefox/joxa/deps/cucumberl/ebin  -pa /home/icefox/my.src/srht/icefox/joxa/deps/erlware_commons/ebin  -pa /home/icefox/my.src/srht/icefox/joxa/deps/getopt/ebin  -pa /home/icefox/my.src/srht/icefox/joxa/deps/proper/ebin \
            -s jxa_bootstrap do_bootstrap /home/icefox/my.src/srht/icefox/joxa/ebin /home/icefox/my.src/srht/icefox/joxa/src/ast/joxa-cmp-expr.ast -s init stop
{error,{badmatch,{error,{6273,erl_parse,["syntax error before: ","'else'"]}}},[{jxa_bootstrap,do_bootstrap,1,[{file,"src/jxa_bootstrap.erl"},{line,7}]},{init,start_it,1,[]},{init,start_em,1,[]},{init,do_boot,3,[]}]}
Runtime terminating during boot ({{badmatch,{error,{6273,erl_parse,["syntax error before: ","'else'"]}}},[{jxa_bootstrap,do_bootstrap,1,[{file,"src/jxa_bootstrap.erl"},{line,7}]},{init,start_it,1,[]},{init,start_em,1,[]},{init,do_boot,3,[]}]})
```

It appears that the AST file(s) contain tokens named `else` in several places, and `else` is now(?) parsed as a token instead of an atom.  Editing all the AST files (including `joxa-compiler.ast`!) to turn `else` into `'else'` appears to fix that, huzzah!

Next it appears the compiler itself tries to build, and fails with:

```erlang
% /usr/bin/erl -noshell  -pa /home/icefox/my.src/srht/icefox/joxa/deps/cf/ebin  -pa /home/icefox/my.src/srht/icefox/joxa/deps/cucumberl/ebin  -pa /home/icefox/my.src/srht/icefox/joxa/deps/erlware_commons/ebin  -pa /home/icefox/my.src/srht/icefox/joxa/deps/getopt/ebin  -pa /home/icefox/my.src/srht/icefox/joxa/deps/proper/ebin -pa /home/icefox/my.src/srht/icefox/joxa/ebin -pa /home/icefox/my.src/srht/icefox/joxa/.eunit -s 'joxa-compiler' main -extra -o /home/icefox/my.src/srht/icefox/joxa/ebin /home/icefox/my.src/srht/icefox/joxa/src/joxa-core.jxa
{error,badarg,
  [{erlang,element,
    [1,
      [quasiquote,
        [
          {'--fun',erlang,'=/='},
          [unquote,a1],
          [unquote,a2]]]],
    [{error_info,#{module=>erl_erts_errors}}]},
   {'joxa-cmp-expr','make-expr',3,
    [{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-expr.jxa"},{line,359}]},
   {'joxa-cmp-expr','do-function-body',6,[{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-expr.jxa"},{line,280}]},
   {'joxa-cmp-defs','make-function1',5,[{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-defs.jxa"},{line,17}]},
   {'joxa-cmp-defs','make-definition',3,[{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-defs.jxa"},{line,53}]},
   {'joxa-compiler','internal-forms',2,[{file,"/Users/emerrit/workspace/joxa/src/joxa-compiler.jxa"},{line,312}]},
   {'joxa-compiler',forms,3,[{file,"/Users/emerrit/workspace/joxa/src/joxa-compiler.jxa"},{line,322}]},
   {'joxa-compiler','do-compile',2,
     [{file,"/Users/emerrit/workspace/joxa/src/joxa-compiler.jxa"},{line,573}]}]}
```

Ok that's the same error we ran into earlier, something handing a bad arg to `erlang:element/2`.  Cause it gets given a list instead of a tuple?  Well that doesn't seem to have changed since OTP 21: <https://www.erlang.org/docs/20/man/erlang#element-2>.  Error points to `joxa-cmp-expr.jxa` line 359, which is:

```
  (case form
    ...
      (arg (when (erlang/and
                  (erlang/is_tuple arg)
                  (== (erlang/element 1 arg) :--fun)))
           (make-fun path0 ctx form))
    ...)
```

hmm, it's checking if the item is a tuple in that guard, why is... oooh `and` doesn't short-circuit evaluate.  So `(erlang/element 1 arg)` gets called even when arg is not a tuple.  Ok fix that and... oh gods I need to fix that in the .ast file don't I.  ...oh well it looks like `andalso` isn't a valid guard expr anyway.  Ummmmm.  ...and `element/2` is???

...why is that `is_tuple(arg) and (element(1, arg) == '--fun'` and not just like...  `{'--fun' _}`?  And I have to figure out how to fix this in the AST.  Ummmmm.

Well worst case I can write some Erlang code to do what I want, compile that to the AST, and splice that in.  Ooooor, find a pattern like what I want elsewhere.  Like in joxa-cmp-ctx.ast:

```clojure 
    ({:--fun _ arity}
     (when (erlang/is_integer arity))
     {raw-ctx (internal-defined-used-function? ref arity raw-ctx)})
```

```erlang
    {c_clause,
       [353,{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
       [{c_tuple,
         [353,{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
         [{c_literal,
           [353,{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
           '--fun'},
          {c_var,
           [353,{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
           '_#:G41982D0'},
          {c_var,
           [compiler_generated,353,
            {file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
           '#:G263798'}]}],
       {c_call,
        [354,{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
        {c_literal,
         [354,{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
         erlang},
        {c_literal,
         [354,{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
         'and'},
        [{c_call,
          [354,{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
          {c_literal,
           [354,{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
           erlang},
          {c_literal,
           [354,{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
           is_integer},
          [{c_var,
            [354,{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
            arity}]},
         {c_call,
          [compiler_generated,353,
           {file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
          {c_literal,[compiler_generated],erlang},
          {c_literal,
           [compiler_generated,353,
            {file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
           '=:='},
          [{c_var,
            [compiler_generated,353,
             {file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
            '#:G263798'},
           {c_var,
            [compiler_generated,353,
             {file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
            arity}]}]},
       {c_tuple,
        [355,{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
        [{c_var,
          [355,{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
          'raw-ctx'},
         {c_apply,
          [355,{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
          {c_var,
           [355,{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
           {'internal-defined-used-function?',3}},
          [{c_var,
            [355,{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
            ref},
           {c_var,
            [355,{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
            arity},
           {c_var,
            [355,{file,"/Users/emerrit/workspace/joxa/src/joxa-cmp-ctx.jxa"}],
            'raw-ctx'}]}]}}
```

...Or, since I know the compiler runs on old OTP versions and they're not too difficult to build, just fix the compiler and have it compile itself.  That would... *probably* be the smart thing to do.

We had a tool for that somewhere.  <https://github.com/asdf-vm/asdf>, that was it.  Add `.tool-versions` file, do `asdf install erlang`, wait for it to build, aaaaaaand now rebar doesn't work, huzzah.  Ok rebuild that with OTP 21 as well, make a copy of it into the joxa dir, clean up all the old beam files, do `make get-deps && make test && make escript` aaaaaaaand... all the tests fail.  Right.  Great.  Okay.  This... this worked before, didn't it???

Ok I just broke the Makefile like a noob.  Theeeeeere we go, now it builds.  And `make bootstrap` does a bootstrap build and writes out the AST files, whiiiiiiich adds piles of noise to the git changes in the file paths and also undoes our `else` fix above.  That's ok, we can fix it for real.  Just rename variables named `else` to `otherwise` I guess.

...what was I even trying to do?  Oh right, weird pattern matching in `joxa-cmp-expr/make-expr`.  Ok that seems easily fixed.

Welp everything seems to build ok with OTP 21 now, so let's try building it with OTP 28!  Bootstrapping is a little fiddly, but it *mostly* seems to work, just dying on undefined reference to `get-stacktrace/0`.  Apparently replaced with <https://www.erlang.org/docs/28/system/expressions.html#try>.  We can stub that out for now; fixing it properly will require changing the `catch` form.  There's a couple places we need it; <https://www.erlang.org/docs/28/apps/erts/erlang.html#raise/3> may also be helpful reference.  Changing Joxa's `try` form will take a bit of work but there's some decent docs on *how* it works, and it doesn't look toooo hard to at least stub it out with something functional-for-now.

That is a project for tomorrow, however.

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
* Make it escape atoms with quotes so you can't generate invalid Erlang AST's by using variables named `else` and such.
* Add backtrace vars to the `catch` form, see <https://www.erlang.org/docs/28/system/expressions.html#try>


## Tooling

* Make very, very sure you can bootstrap it and get the correct results out of it before starting to tinker with the bootstrap process.
* Needs updating to rebar3
* Get rid of the makefiles while we're at it
* Not yet sure whether shipping AST files for the bootstrapped compiler is brilliant or bonkers.  BEAM files may be easier?  Or at least not need a shim to load?  Not sure.
* Docs are incomplete and annoying.  The longest section is about how to format the source code.  Need updating.
* Docs use an old version of Sphinx.  Valid, but now would be better to rebuild them using ExDoc.  Not sure how well ExDoc supports random languages though.
* Honestly would be nice if it just compiled to readable Erlang, like Fennel does.  Could we even make an antifennel-like Erlang-to-Joxa compiler?  Maybe!
* Can we do anything with `dialyzer`?  Maybe.  That's a bit of a future subproject.
* Hoo boy the backtraces could use some work.
* If we keep the AST compilation, try to make it output only the relative file path in the line numbers please, not the absolute path.  Makes git diff's much cleaner...
* Gensym's too, plz.


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
