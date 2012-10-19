# <b>Rubuild</b> -- A smart build system written in Ruby

<b>Rubuild</b> is a brand new build system written from scratch in pure Ruby. It is
designed to be a replacement for <b><code>Make</code></b>, <b><code>automake</code></b>,
<b><code>autoconf</code></b>, <b><code>libtool</code></b> and similar tools on some
common platforms. It is currently targeted at projects that are written in C/C++ and has
been tested on Linux and Mac/OSX.

## Table of Contents

1. Installing Ruby 1.9.X and Tokyo Cabinet
2. How to build demo projects
3. Rationale
4. Features
5. How to build your projects
6. Architecture
7. Limitations
8. Odds and Ends

### Installing Ruby 1.9.X and Tokyo Cabinet

<b>Rubuild</b> needs Ruby 1.9.X which itself has a couple of prerequisites: the
development libraries for <b>zlib</b> and <b>libreadline6</b>
(packages <b><code>zlib1g-dev</code></b> and <b><code>libreadline6-dev</code></b>
on debian-based systems). It also needs <b>Tokyo Cabinet</b> (a "NoSQL" database),
including its Ruby bindings.

If you are a Ruby veteran and are already familiar with the process of installing
it, just make sure the above pre-requisites are satisfied.

If you are new to Ruby, a small shell script <b><code>prereq.sh</code></b> is provided
to simplify the process of installing the prerequisites on Debian-based Linux systems.
Just change to the directory where you want the archives unpacked and built (e.g.
<b><code>cd ~/src</code></b>) and give it an (optional) argument which is the install
location (default: <b><code>/usr/local</code></b>). For example:

    mkdir ~/src; cd ~/src
    <path>/prereq.sh

After this, you should be able verify the Ruby version with:

    ruby -v

### How to build demo projects

First, retrieve the Rubuild sources with:

    git clone https://github.com/amberarrow/rubuild

The <b><code>projects</code></b> subdirectory under <b><code>rubuild</code></b> has a few
directories for building various open-source projects. Currently there are three:

* <b><code>HelloWorld</code></b>
* <b><code>snappy</code></b>
* <b><code>tokyocabinet</code></b>

Each directory has a <b><code>README</code></b> file describing how to build it.

<b><code>HelloWorld</code></b> has a small C++ program and a C library and is part of
the <b>Rubuild</b> sources.
Build it like this (details in <b><code>projects/HelloWorld/README</code></b>):

    cd rubuild/projects/HelloWorld
    ruby -w hello_world.rb -s $PWD/../../HelloWorld -o /var/tmp/rubuild/HelloWorld

<b><code>Snappy</code></b> is a fast C++ compression library available at
<b><code>http://code.google.com/p/snappy/</code></b>
Building it is similar (details in <b><code>projects/snappy/README</code></b>):

    cd rubuild/projects/snappy
    ruby -w snappy.rb -s <snappy-src-dir> -o /var/tmp/rubuild/snappy -b rel

Tokyo Cabinet is a fast "NoSQL" database written in C. It is available at
<b><code>http://fallabs.com/tokyocabinet/tokyocabinet-1.4.48.tar.gz</code></b>
Building it is also similar (details in <b><code>projects/tokyocabinet/README</code></b>):

    cd rubuild/projects/tokyocabinet
    ruby -w tc.rb -s <tc-src-dir> -o /var/tmp/rubuild/tokyocabinet -b rel

### Rationale:

The motivation for writing <b>Rubuild</b> is to transcend the limitations of a tool like
<b>Make</b>
(and its numerous siblings and look-alikes) with its declarative semantics that severely
limit its usability, flexibility and programmability. Over the years, Make has been
extended by a patchwork of enhancements to provide conditionals, loops and function
calls with highly idiosyncratic syntax that makes it awkward to use for even a project
of moderate complexity. Additionally, a vast array of equally awkward tools such as
<b><code>automake</code></b>, <b><code>autoconf</code></b> and
<b><code>libtool</code></b> have sprung up around it resulting in substantial
increases in complexity. Various websites discuss the pain associated with these tools,
for example:

* <b><code>http://voices.canonical.com/jussi.pakkanen/tag/pain/</code></b>

* <b><code>http://titusd.co.uk/2010/08/29/rake-builder/</code></b>

In contrast, project configuration files in Rubuild are Ruby scripts so the full power
of a clean, well-designed, object-oriented, fully dynamic programming language is
available along with a wealth of standard libraries. A specific design goal, therefore,
was to eschew declarative data files (e.g. XML files, Makefiles, properties files)
completely and use code files for everything with the sole exception of the persistence
database.

This approach provides a number of benefits, among them:

+ Fine-grained control over the specific options used to compile, assemble, or link
  individual files. In contrast, conventional Makefiles use pattern rules which makes
  it very difficult to control options at the level of individual files resulting in
  many unnecessary options being used.

  Another use case is a situation where a build is using a number of warning flags
  along with the <b><code>-Werror</code></b> option (which causes warnings to be treated
  as errors). When a new version of the compiler arrives, it causes build failures due
  to more stringent checking of warning-conditions. With <b>Rubuild</b>, in such cases,
  we can selectively disable <b><code>-Werror</code></b> on the specific
  file(s) which cause build failure rather than for the entire build.

+ Detection of erroneous or suboptimal compiler or linker option combinations. For
  example, a common mistake is to use the <b><code>-shared</code></b> option when
  linking an executable.
  The resulting file will not be runnable because what was created was a
  *dynamic library*!
  Another example is omitting the required option <b><code>-fPIC</code></b> when building
  dynamic libraries. Yet another is using the <b><code>-fPIC</code></b> which compiling
  files for inclusion in static libraries: though this is not a fatal error, it causes
  some performance degradation since it introduces an unnecessary extra indirection to
  every variable and function reference.

+ Persistence enables <b><code>Rubuild</code></b> to detect changes in options and
  trigger a rebuild; in contrast, if <b><code>Make</code></b> is run once with one set
  of say, <b><code>CFLAGS</code></b> supplied on the command
  line and immediately re-run with a different set, it will not rebuild any of the
  targets since it has no persistence mechanism to detect the change in options.

+ Better logging and explanations of why a particular target was rebuilt. With
  <b><code>Make</code></b>, it can sometimes be difficult to deduce the logic behind
  some actions (e.g. why was <b><code>foo.o</code></b> not rebuilt ? Why was
  <b><code>baz.o</code></b> rebuilt ?)
  even with debugging enabled, because of the complex way the decision threads its way
  through implicit rules, static pattern rules, single and double colon rules and
  multiple flavors of variable evaluation semantics.

+ Decoupling the location of the source directory from the directory where the
  objects are generated and each from the location of the build tool itself. This allows
  <b><code>Rubuild</code></b> to operate in a completely non-intrusive manner since it
  make no changes whatsover to the source directories.

### Features

Here is a brief feature summary of Rubuild features:

+ All build files are Ruby programs so arbitrary customization and tweaking of the
  build process should, in theory, be easy.
+ Fine-grained control over compiler and linker options used on individual files.
+ Location of build files is decoupled from the location of the sources and both are
  decoupled from the directory where generated objects are placed.
+ Uses a thread pool for parallel builds.
+ Fast -- in our informal time trials, <b><code>Rubuild</code></b> is as fast as and
  often faster than <b><code>Make</code></b> with the same parallel build factor.
+ Supports 3 build types: <b>debug</b>, <b>optimized</b>, <b>release</b>. The last is the
  same as the penultimate but it strips symbols from the object files.
+ Supports 2 link types: <b>dynamic</b> and <b>static</b>.
+ Objects of each build and link type use different file extensions so they can all
  simultaneously coexist; hence, when you switch from one type to another, you don't
  have to rebuild the entire project.
+ Has detailed knowledge of GCC options and checks the option set for errors or
  inconsistencies.
+ Uses standard Ruby logging.
+ Prints histogram of build times to log file
+ Prints histogram of dependency counts to log file.
+ Shows a commandline progress indicator with the number of remaining targets to build.
+ Uses a "NoSQL" database (Tokyo Cabinet) for persistence, so targets will be rebuilt
  if there is any change to the options used to build them.
+ Tested on Linux and Mac/OSX.

### How to build your projects

The easiest way is to emulate some of the demo projects. Some knowledge of Ruby is
obviously required. We hope to simplify this process soon, but for now we suggest the
following steps to port your project, say <b><code>xyz</code></b>, to
<b><code>Rubuild</code></b>:

+ Create two Ruby files by copying the corresponding files from
  <b><code>HelloWorld</code></b> (or one of the
  other demo projects): <b><code>xyz_config.rb</code></b> and <b><code>xyz.rb</code></b>;
  the first should contain global configuration (such as compiler and linker flags)
  across the entire project. If some files need different options, you can make these
  adjustments later in the specific subprojects that contain these files.

  The second should define one class per subproject derived from the class named
  <b><code>Bundle</code></b>. At least one such class _must_ be present.

+ A subproject is, roughly speaking, a subdirectory of the main project with source
  files that form libraries and executables. The <b><code>dir_root</code></b> instance
  variable holds the name of this subdirectory (which can just be '.' if all sources are
  in the main project directory). <b><code>Rubuild</code></b> will automatically scan
  all files and directories under the root for C or C++ files.

+ The derivative Bundle class should then define include and exclude lists (to limit the
  files and directories that are searched), libraries and executables to be built and
  the list of default targets. The <b><code>setup</code></b> method must be present and
  is automatically
  invoked at the appropriate time; additional methods that are invoked within setup
  may be defined as needed.

+ As an example, suppose your project has subdirectories A, B, C and D where the first
  two have source files that are aggregated into libraries <b><code>libA</code></b> and
  <b><code>libB</code></b> and you want
  <b><code>Rubuild</code></b> to ignore completely the last two; assume further that
  you also have some source files in the main project directory that need to be compiled
  and built into an executable. You would proceed as follows:

    * Define three subclasses of Bundle in <b><code>xyz.rb</code></b>:
    <pre><code>
        class LibA < Bundle  ...  end
        class LibB < Bundle  ...  end
        class Xyz  < Bundle  ...  end
    </code></pre>

    * Within each class, define the libraries and executables to be built from files
      in that directory. Within the last you should also add C and D to the exclude list
      to prevent scanning of those directories.

+ Within the setup method you can customize options for individual files; for example,
  to add the <b><code>-Wtype-limits</code></b> warning option when compiling
  <b><code>foo.cc</code></b> and to remove the <b><code>-Wshadow</code></b> warning
  option (which is presumably part of the global project defaults defined in
  <b><code>xyz_conf.rb</code></b>:
    <pre><code>
    add_target_options( :target  => ['foo', :obj],
                        :options => ['-Wtype-limits'] )
    delete_target_options( :target  => ['foo', :obj],
                           :options => ['-Wshadow'] )
    </code></pre>

  Similarly, to add a different include path on Mac versus Linux (pre-processor options,
  typically <b><code>-I</code></b>, <b><code>-D</code></b> and <b><code>-U</code></b>,
  need to be explicitly tagged as such) :

    <pre><code>
    opt = [ @@system.darwin? ? '-I/opt/freetype/include/freetype2'
                             : '-I/usr/include/freetype2' ]
    add_target_options( :target  => ['MyFontManager', :obj],
                        :type    => :cpp,
                        :options => opt )
    </code></pre>

### Architecture

The main class is <b><code>Build</code></b> which also serves as the encapsulation
namespace. Its definition therefore is distributed across multiple files with the core
definitions in <b><code>build.rb</code></b>; the command line parsing is also done in
this file. Here is a table that summarizes the functionality embodied in each file:

<table border="1">
<tr><th>File</th> <th>Function</th></tr>
<tr><td>build.rb</td>     <td>Core driver code; also command line parsing</td></tr>
<tr><td>options.rb</td>   <td>Classes for numerous GCC options</td></tr>
<tr><td>targets.rb</td>   <td>Classes for various target types</td></tr>
<tr><td>db.rb</td>        <td>Persistence database</td></tr>
<tr><td>features.rb</td>  <td>Classes for checking presence of features</td></tr>
<tr><td>histogram.rb</td> <td>Simple histogram class</td></tr>
<tr><td>system.rb</td>    <td>OS and system capabilities</td></tr>
<tr><td>common.rb</td>    <td>Common utilities including logger configuration</td></tr>
</table>

We plan to add much more detail here shortly but in the interim there are comments on
all non-trivial parts of the code so it should be very readable if you know some Ruby.

### Limitations

+ Currently limited to C/C++ (with some assembler) projects in Linux and Unix-like
  environments.
+ There is no equivalent of <b><code>make install</code></b>; we hope to remedy this soon.
+ There is also no equivalent of <b><code>make clean</code></b> but this is less of an
  issue since you can get the desired effect by simply removing the entire object
  directory.

### Odds and Ends

+ When you start the build you'll see the message
  <b><code>Detecting dependencies ...</code></b> for a few
  seconds; thereafter you should see a progress indicator in the form of a countdown
  spinner showing the number of targets that remain to be built. Note that this spinner
  may reach zero and bounce back up to a small number and count down to zero again; this
  is normal and no cause for alarm.

Finally, <b><code>Rubuild</code></b> is still in its infancy and has only been lightly
tested, so it is likely that it will undergo significant changes in the weeks ahead.

We welcome feedback, so please feel free to send your comments to amberarrow on gmail.

Thanks!
