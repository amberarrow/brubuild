#!/usr/bin/ruby -w

# Ruby-based build system
# Author: ram (Munagala V. Ramanath)
#
# Classes associated with various assembler, compiler and linker options
#

%w{ set common.rb }.each { |f| require f }

class Build    # main class and namespace
  # GCC has many different kinds of options:
  # 1. Some start with a double hyphen (e.g. --param) and some with a single hyphen
  #    e.g. -static
  #
  # 2. Some are aliases, e.g. -foptimize-register-move, -fregmove
  #
  # 3. Some have different strings attached to the option name (call them parameters);
  #    the paramters can be either numbers or strings, e.g. -O2, -Ofast
  #
  # 4. The parameter may be run together with the option (e.g. -UFoo) or may have a
  #    separating space (e.g. -include foo)
  #
  # 5. In some cases, the parameter may be negated with a "no-" prefix
  #    (e.g. -Wshadow, -Wno-shadow)
  #
  # 6. Sometimes these parameters are attached to the option with a separating '='
  #    e.g. -std=gnu99
  #
  # 7. Some of these parameters have additional strings attached to them (call them
  #    values) with a separaing '=', e.g. -Werror=shadow
  #
  # 8. Sometimes order is relevant (e.g. -Ia, -Ib) and sometimes not, e.g. -include is
  #    processed after all -D and -U options regardless of where it appears.
  #
  # 9. Some consecutive options form groups that must be kept together,
  #    e.g. -Wl,-rpath -Wl,/opt/foo/lib
  #
  # Semantically we have the following oddities:
  #
  # 1. The same option name is used for different purposes, e.g.:
  #      -fdollars-in-identifiers is a pre-processor option
  #      -fdce is an optimization option
  #      -fno-diagnostics-show-option is a language-independent opton
  # 2. The various option groups listed in the gcc man page are neither complete
  #    (the set shown under pre-processor options) nor mutually exclusive, e.g.
  #    -- some of the overall options (e.g. -E) are pre-processor options
  #    -- some options apply to both compiler and and linker (e.g. -fPIC, -flto)
  #    -- some options mean different things on different platforms (e.g. ...)
  #

  # base class for various kinds of options (useful because we can define hash, ==, etc.
  # here for the whole hierarchy)
  #
  class Option
    # name
    #    Name of option including any leading hyphens, e.g. '-v', '--param', etc.
    #
    # option_kind
    #    Kind of option: :preprocessor, :compiler, :linker, :other
    #
    # param_kind
    #    Whether a parameter is needed and what kind
    #    :none, :required, :optional, :single, :multi
    #
    # param
    #    Entire parameter if any including 'no-' prefix if present; this makes
    #    comparisons easier -- we need to compare only the name and the param
    #
    # neg
    #    true if param has 'no-' prefix; :value if the value has 'no-' prefix; undefined
    #    or nil if there is no negation involved.
    #
    # key, value
    #    There are 2 cases:
    #    Case A:
    #      No '=' present in param; here, key is undefined if the param does NOT
    #      take a 'no-' prefix. If it does, key is param with the 'no-' prefix, if any,
    #      stripped (so key may equal param)
    #    Case B:
    #      key=value parts of param if any (undefined otherwise); key has any 'no-'
    #      prefix removed; value is unmodified (negation prefix is not normally allowed
    #      in the value).
    #      Double negatives are not allowed so we will never have the
    #      'no-' present in both (so -Wno-error=no-shadow is not permitted). If a value
    #      is present, it always has a preceding '=' to separate it from the key.
    #
    # sep
    #    required separator character, if any, between name and parameter; set in
    #    derived classes if present. Currently, either undefined, blank or '=' (see below)
    #
    # Examples:
    # ========
    # For option '-Dxyz=abc':
    #   name is '-D', param is 'xyz=abc', key is 'xfyz', value is 'abc', sep is undefined
    #
    # For option '-std=gnu99':
    #   name is '-std', param is 'gnu99', key/value are undefined, sep is '='
    #
    # For option '-Wno-error=shadow':
    #   name is '-W', param is 'no-error=shadow', neg is true,
    #   key is 'error', value is 'shadow'
    #
    # For option '-Werror=shadow':
    #   name is '-W', param is 'error=shadow', neg is false,
    #   key is 'error', value is 'shadow'
    #
    # For option '--param max-inline-insns-single=1800':
    #   name is '--param', param is 'max-inline-insns-single=1800',
    #   key is 'max-inline-insns-single', value = '1800', sep is ' '
    #
    attr :name, :option_kind, :param_kind, :param, :sep, :key, :value

    # since we use gcc to assemble .S files, we use the :compiler for assembler options
    OPTION_KINDS = Set[:preprocessor, :assembler, :compiler, :linker, :other]

    # (currently unused)
    # we follow the groups in the gcc docs
    OPTION_GROUPS = Set[
                        :overall,            # overall
                        :c,                  # C language
                        :cxx,                # C++ language
                        :objc,               # Objective-C/Objective-C++ language
                        :diagnostics,        # language independent options
                        :warn,               # warning
                        :warn_c_objc,        # warning options for C/Objective-C only
                        :debug,              # debug
                        :opt,                # optimization
                        :pre_processor,      # pre-processor
                        :assembler,          # assembler
                        :linker,             # linker
                        :directory,          # directory
                        # these are subgroups of "Machine Dependent Options"
                        :machine_darwin,     # darwin (Mac OS)
                        :machine_linux,      # GNU/Linux
                        :machine_i386,       # i386/x86-64
                        :code_gen,           # code generation
                       ]

    # whether the option needs parameters
    PARAM_KINDS  = Set[:none, :required, :optional, :single, :multi]

    def self.[]( a_name, a_o_kind, a_p_kind, a_param = nil,
                 a_neg = nil, a_sep = nil, a_key = nil, a_val = nil )
      new a_name, a_o_kind, a_p_kind, a_param, a_neg, a_sep, a_key, a_val
    end

    # a_name -- name of option
    # a_o_kind -- kind of option
    # a_p_kind -- kind of parameter
    # a_param -- full parameter string if any
    # a_sep -- separator between name and param if any
    # a_key -- key if any
    # a_val -- value if any
    #
    def initialize a_name, a_o_kind, a_p_kind, a_param = nil,
                   a_neg = nil, a_sep = nil, a_key = nil, a_val = nil
      raise "Need name" if !a_name
      s = a_name.strip
      raise "Empty name" if s.empty?
      raise "Need option_kind" if !a_o_kind
      raise "Invalid option kind: #{a_o_kind}" if !OPTION_KINDS.include? a_o_kind
      raise "Need param_kind" if !a_p_kind
      raise "Invalid param kind: #{a_p_kind}" if !PARAM_KINDS.include? a_p_kind
      raise "Need parameter" if !a_param && :required == a_p_kind
      raise "Parameter not allowed" if a_param && :none == a_p_kind

      # for -Wno-inline, key is 'inline' but there is no value
      #raise "Key/value must be both present or both absent" if a_key.nil != a_val.nil?

      raise "Unusual separator: #{a_sep}" if a_sep && '=' != a_sep && ' ' != a_sep

      @name, @option_kind, @param_kind = s, a_o_kind, a_p_kind
      @param = a_param if a_param
      @neg = a_neg if a_neg
      @sep = a_sep if a_sep
      @key = a_key if a_key
      @value = a_val if a_val
    end  # initialize

    # dup each field that can be duplicated. Fixnum, TrueClass, FalseClass, Symbol etc.
    # cannot (and need not) be duplicated
    #
    # When options are changed on a per-target basis, we need to duplicate option sets.
    #
    def initialize_copy( orig )
      instance_variables.each { |v|
        w = instance_variable_get( v )

        # Symbol responds to dup but says "can't dup Symbol" if you invoke it;
        # similarly TrueClass and FalseClass
        #
        next if !w.respond_to?( :dup ) || w.is_a?( Symbol ) || true == w || false == w
        instance_variable_set( v, w.dup )
      }
    end  # initialize_copy

    def to_s    # convert to string
      s = @name
      return s if !defined?( @param ) || @param.nil?

      # We have a parameter; the default behavior is to have no space separating the
      # name from the parameter; this is appropriate for many options,
      # e.g. -Dfoo, -Ufoo, -Wfoo
      # But some need a blank separator of a blank (e.g. "--param foo=bar") or a '='
      # (e.g. "-std=gnu99")
      # We will never have _two_ equal signs in an option: -fbaz=foo=baz
      #
      s += @sep if defined? @sep
      s += @param    # key/value, if any, are part of param
    end  # to_s

    # define <=> if needed

    def is_cpp    # return true iff this is a pre-processor option
      [OptionDefine, OptionUndefine, OptionInclude].include? self.class
    end  # hash

    # comparing options -- used for example when user tries to add an option
    def hash
      instance_variables.inject( 17 ) { |m, v| 37 * m + instance_variable_get( v ).hash }
    end  # hash

    def == other
      return false if self.class != other.class || self.hash != other.hash
      idx = instance_variables.index { |v|
        instance_variable_get( v ) != other.instance_variable_get( v )
      }
      return idx.nil?
    end  # ==

    def eql? other
      self == other
    end  # eql?
  end  # Option

  class OptionWarning < Option    # -Wfoo or -Wno-foo
    # We currently use these warning options for C in this order:
    #   -Wempty-body -Wtype-limits -fdiagnostics-show-option -Wall -Wpointer-arith
    #   -Wshadow -Wstrict-prototypes -Werror

    # options in -Wextra (same as plain -W)
    EXTRA = %w[
                clobbered
                empty-body
                ignored-qualifiers
                missing-field-initializers
                missing-parameter-type    # C only
                old-style-declaration     # C only
                override-init
                sign-compare
                type-limits
                uninitialized
                unused-parameter            # only with -Wunused or -Wall
                unused-but-set-parameter    # only with -Wunused or -Wall
             ].to_set

    # options in -Wall
    ALL = %w[
              address
              array-bounds    # only with -O2
              c++11-compat
              char-subscripts
              enum-compare    # in C/Objc; this is on by default in C++
              implicit-int    # C and Objective-C only)
              implicit-function-declaration    # C and Objective-C only
              comment
              format
              main                   # only for C/ObjC and unless -ffreestanding)
              maybe-uninitialized
              missing-braces
              nonnull
              parentheses
              pointer-sign
              reorder
              return-type
              sequence-point
              sign-compare           # only in C++
              strict-aliasing
              strict-overflow=1
              switch
              trigraphs
              uninitialized
              unknown-pragmas
              unused-function
              unused-label
              unused-value
              unused-variable
              volatile-register-var
           ].to_set

    # all known warning options
    PARAM_W = %w[
                   abi
                   address
                   aggregate-return
                   all
                   array-bounds
                   assign-intercept
                   attributes
                   bad-function-cast
                   builtin-macro-redefined
                   cast-align
                   cast-qual
                   char-subscripts
                   clobbered
                   comment
                   comments
                   conversion
                   conversion-null
                   ctor-dtor-privacy
                   declaration-after-statement
                   delete-non-virtual-dtor
                   deprecated
                   deprecated-declarations
                   disabled-optimization
                   div-by-zero
                   double-promotion
                   effc++
                   empty-body
                   endif-labels
                   enum-compare
                   error         # takes optional "=<foo>"
                   extra
                   fatal-errors
                   float-equal
                   format
                   format-contains-nul
                   format-extra-args
                   format-nonliteral
                   format-nonliteral
                   format-security
                   format-y2k
                   format-zero-length
                   format=2            # treat this literally since only 2 is allowed
                   frame-larger-than
                   free-nonheap-object
                   ignored-qualifiers
                   implicit
                   implicit-function-declaration
                   implicit-int
                   init-self
                   inline
                   int-to-pointer-cast
                   invalid-offsetof
                   invalid-pch
                   jump-misses-init
                   larger-than         # takes "=<len>"
                   logical-op
                   long-long
                   main
                   maybe-uninitialized
                   missing-braces
                   missing-declarations
                   missing-field-initializers
                   missing-format-attribute
                   missing-include-dirs
                   missing-parameter-type
                   missing-prototypes
                   multichar
                   narrowing
                   nested-externs
                   non-virtual-dtor
                   nonnull
                   normalized         # takes "=<none|id|nfc|nfkc>"
                   old-style-cast
                   old-style-declaration
                   old-style-definition
                   overflow
                   overlength-strings
                   overloaded-virtual
                   override-init
                   packed
                   packed-bitfield-compat
                   padded
                   parentheses
                   pedantic-ms-format
                   pmf-conversions
                   pointer-arith
                   pointer-sign
                   pointer-to-int-cast
                   pragmas
                   protocol
                   redundant-decls
                   reorder
                   return-type
                   selector
                   sequence-point
                   shadow
                   sign-compare
                   sign-conversion
                   sign-promo
                   stack-protector
                   stack-usage
                   strict-aliasing    # takes optional "=n" with n in 1..3
                   strict-null-sentinel
                   strict-overflow    # takes optional "=n" with n in 1..5
                   strict-prototypes
                   strict-selector-match
                   suggest-attribute  # takes "=const|noreturn|pure"
                   switch
                   switch-default
                   switch-enum
                   sync-nand
                   system-headers
                   traditional
                   traditional-conversion
                   trampolines
                   trigraphs
                   type-limits
                   undeclared-selector
                   undef
                   uninitialized
                   unknown-pragmas
                   unsafe-loop-optimizations
                   unsuffixed-float-constants
                   unused
                   unused-but-set-parameter
                   unused-but-set-variable
                   unused-function
                   unused-label
                   unused-local-typedefs
                   unused-macros
                   unused-parameter
                   unused-result
                   unused-value
                   unused-variable
                   useless-cast
                   variadic-macros
                   vector-operation-performance
                   vla
                   volatile-register-var
                   write-strings
                   zero-as-null-pointer-constant
                 ].to_set

    def self.[]( a_param )
      raise "Missing warning type" if !a_param

      # add checks for =arg in a_param
      a = a_param.split '='
      if 2 == a.size    # have an argument
        k, v = a[ 0 ].strip, a[ 1 ].strip
        raise "Empty key in #{a.param}" if k.empty?
        raise "Empty value in #{a.param}" if v.empty?

        # get positive form of key by removng any leading negation
        kp = k.sub( /^no-/o, '' )
        negated = k.size != kp.size
        raise "Unknown warning: #{a_param}" if !PARAM_W.include? kp

        # These warnings currently take an argument:
        # error -- argument is name of warning
        # format -- treat 'format=2' literally since only 2 is allowed as an argument
        # larger-than -- argument is integer
        # normalized -- argument is one of none|id|nfc|nfkc
        # strict-aliasing -- argument is in 1..3
        # strict-overflow -- argument is in 1..5
        # suggest-attribute -- argument is one of const|noreturn|pure
        #
        case kp
        when 'error'    # NOTE: double negatives are not valid: -Wno-error=no-shadow
          raise "Unknown warning: #{v}" if !PARAM_W.include? v
        when 'format'
          raise "Bad value #{v} in #{a_param}" if '2' != v
        when 'larger-than'
        when 'normalized'
          raise "Bad value #{v} in #{a_param}" if v !~ /^(?:none|id|nfc|nfkc)$/o
        when 'strict-aliasing'
          vn = v.to_i
          raise "Bad value #{v} in #{a_param}" if !(1..3).include? vn
        when 'strict-overflow'
          vn = v.to_i
          raise "Bad value #{v} in #{a_param}" if !(1..5).include? vn
        when 'suggest-attribute'
          raise "Bad value #{v} in #{a_param}" if v !~ /^(?:const|noreturn|pure)$/o
        else raise "Warning #{kp} does not take an argument"
        end  # case
        new a_param, kp, negated, v

      else    # no "<key>=<value>" suffix

        # get positive form of param by removng any leading negation
        nm = a_param.sub( /^no-/o, '' )
        negated = a_param.size != nm.size
        raise "Unknown warning: #{a_param}" if !PARAM_W.include? nm
        new a_param, nm, negated
      end
    end  # self.[]

    # a_param -- full parameter, e.g. 'no-error=unused'; may be identical to a_key
    # a_key   -- type of warning excluding 'no-' prefix, e.g. 'error'
    # a_neg   -- true iff we got the negated form, e.g. 'no-inline'
    # a_val -- for -Wno-foo=bar, a_key is 'foo', a_val is 'bar'
    #
    def initialize( a_param, a_key, a_neg, a_val = nil )
      # ctor may be invoked directly so we do full checking here
      raise "a_key is void"  if a_key.nil?  || a_key.empty?
      raise "Unknown warning: #{a_param}" if !PARAM_W.include? a_key
      raise "a_param is void" if a_param.nil? || a_param.empty?
      raise "a_neg is not Boolean" if ![true, false].include? a_neg

      super '-W', :compiler, :required, a_param, a_neg, nil, a_key, a_val
    end  # initialize

  end  # OptionWarning

  # DESIGN: Define one class per group of similar options; sometimes we create a class
  # for a single option (e.g. -fPIC). Might have to refactor later.

  # Pre-processor option to define/undefine symbols: -DXYZ=abc or -UFOO
  class OptionDefine < Option

    def self.[]( a_name, a_param )
      if '-D' == a_name
        raise "Need symbol name to define" if !a_param || a_param.empty?
        a = a_param.split '='
        raise "Bad define option: #{a_param}" if a.size < 1 || a.size > 2
        k = a[ 0 ].strip
        raise "Empty symbol in #{a_param}" if k.empty?
        if 2 == a.size
          v = a[ 1 ].strip
          raise "Empty value in #{a_param}" if v.empty?
        else
          v = nil
        end
      elsif '-U' == a_name
        raise "Need symbol name to undefine" if !a_param || a_param.empty?
        k, v = nil, nil
      else raise "Bad macro option: #{a_name}"
      end
      new a_name, :preprocessor, :required, a_param, k, v
    end  # []

    def initialize a_name, a_o_kind, a_p_kind, a_param, a_key, a_value
      super a_name, a_o_kind, a_p_kind, a_param, nil, nil, a_key, a_value
    end  # initialize
  end  # OptionDefine

  # Include directory path: -Ix/y/z (NOTE: order of these options is important)
  class OptionInclude < Option
    def self.[]( a_param )
      raise "Need include path" if !a_param || a_param.empty?
      # directory may not exist when this option is created; it may be generated later
      #File.check_dir a_param
      new '-I', :preprocessor, :required, a_param
    end
  end  # OptionInclude

  class OptionMachine < Option    # -mfoo (compiler, assembler, or linker)
    PARAM_M = Set[ 'sse2', '64', '32']

    def self.[]( a_param, c_or_a_or_l = :compiler )
      raise "Need machine parameter" if !a_param || a_param.empty?
      raise "Bad machine parameter: #{a_param}" if !PARAM_M.include? a_param
      new '-m', c_or_a_or_l, :required, a_param
    end
  end  # OptionMachine

  # -fPIC is both compiler and linker option!
  class OptionPIC < Option
    def self.[]( c_or_l )
      raise "Bad PIC type: #{c_or_l}" if c_or_l != :compiler && c_or_l != :linker
      new '-fPIC', c_or_l, :none
    end
  end  # OptionPIC

  # -fsigned-char is a compiler option
  class OptionSignedChar < Option
    def self.[]()
      new '-fsigned-char', :compiler, :none
    end
  end  # OptionSignedChar

  # -funsigned-char is a compiler option
  class OptionUnsignedChar < Option
    def self.[]()
      new '-funsigned-char', :compiler, :none
    end
  end  # OptionUnsignedChar

  # -fno-common is compiler option on OSX
  class OptionNoCommon < Option
    def self.[]()
      new '-fno-common', :compiler, :none
    end
  end  # OptionNoCommon

  # -flto is both compiler and linker option!
  class OptionLTO < Option
    def self.[]( c_or_l )
      raise "Bad lto type: #{c_or_l}" if c_or_l != :compiler && c_or_l != :linker
      new '-flto', c_or_l, :none
    end
  end  # OptionLTO

  class OptionStd < Option    # -std=...
    PARAM_STD = Set[ 'c89', 'c90', 'iso9899:1990', 'iso9899:199409',
                     'c99', 'c9X', 'iso9899:1999', 'iso9899:199x',
                     'c11', 'c1x', 'iso9899:2011',
                     'gnu89', 'gnu90', 'gnu99', 'gnu9x', 'gnu11', 'gnu1x',
                     'c++11', 'c++0x', 'c++1y',
                     'gnu++11', 'gnu++0x', 'gnu++1y'
                   ]
    def self.[]( a_param )
      raise "Need std parameter" if !a_param || a_param.empty?
      raise "Bad std parameter: #{a_param}" if !PARAM_STD.include? a_param
      new a_param
    end

    def initialize a_param
      super '-std', :compiler, :required, a_param, nil, '='
    end  # initialize

  end  # OptionStd

  class OptionDebug < Option    # -g, -g0, -gstabs, ...
    # Assembler may also need this option
    def self.[]( a_kind = :compiler, a_param = nil )
      p = a_param ? a_param.strip : nil
      new '-g', a_kind, :optional, p
    end
  end  # OptionDebug

  class OptionOptimize < Option    # -O? or -fno-default-inline
    PARAM_O = Set['0', '1', '2', '3', 's' 'fast']

    # we currently use these options (add more as needed):
    #   -fdiagnostics-show-option (handled as OptionDiagnostic below)
    #   -finline-functions
    #   -fno-strict-aliasing
    #
    PARAM_f = Set[ 'inline-functions',  'no-inline-functions',
                   'strict-aliasing',   'no-strict-aliasing' ]

    def self.[]( a_name, a_param, a_kind = :compiler )
      if '-O' == a_name
        raise "Bad -O parameter: #{a_param}" if a_param && !PARAM_O.include?( a_param )
      elsif '-f' == a_name
        raise "Bad -f parameter: #{a_param}" if a_param && !PARAM_f.include?( a_param )
      else
        raise "Bad optimize option: #{a_name}"
      end
      new a_name, a_kind, :optional, a_param
    end
  end  # OptionOptimize

  class OptionOptimizeParam < Option    # --param key=value

    # we currently use (add more as needed):
    #     max-inline-insns-single
    #
    PARAM_NAME = Set['max-inline-insns-single']

    def self.[]( a_param )
      raise "Need param parameter" if !a_param || a_param.empty?
      a = a_param.split '='
      raise "Bad param option: #{a.param}" if a.size != 2
      a[ 0 ].strip!; a[ 1 ].strip!
      raise "Empty name in #{a.param}" if a[ 0 ].empty?
      raise "Unrecognized name: #{a[0]}" if !PARAM_NAME.include?( a[ 0 ] )
      new a_param, a[ 0 ], a[ 1 ]
    end

    def initialize a_param, a_key, a_val
      super '--param', :compiler, :required, a_param, nil, ' ', a_key, a_val
    end  # initialize

  end  # OptionOptimizeParam

  # Options to Control Diagnostic Messages Formatting
  #
  class OptionDiagnostic < Option
    # we currently use these (add more as needed):
    #     -fdiagnostics-show-option
    #
    PARAM_W = Set['diagnostics-show-option']

    def self.[]( a_param )
      raise "Missing diagnostic type" if !a_param
      p = a_param.sub( /^no-/o, '' )
      negated = a_param.size != p.size
      raise "Unknown diag option: #{a_param}" if !PARAM_W.include? p
      new '-f', :compiler, :required, a_param, negated, nil, p
    end
  end  # OptionDiagnostic

  # Special case of assembler pass-through
  #   -Wa,--noexecstack
  #
  class OptionNoExecStack < Option
    def self.[]
      new '-Wa,--noexecstack', :compiler, :none
    end
  end  # OptionNoExecStack

  # --------------------------------------------------
  # Linker-only options -- BEGIN
  # NOTE: Some options are for both compiling and linking (e.g. -fPIC); they are
  #       defined above
  # --------------------------------------------------

  # shared libraries
  class OptionShared < Option
    def self.[]
      new '-shared', :linker, :none
    end
  end  # OptionShared

  class OptionNoStdLib < Option
    def self.[]
      new '-nostdlib', :linker, :none
    end
  end  # OptionNoStdLib

  # OSX dynamic libraries
  class OptionDynamicLib < Option
    def self.[]
      new '-dynamiclib', :linker, :none
    end
  end  # OptionDynamicLib

  # static libraries
  class OptionStatic < Option
    def self.[]
      new '-static', :linker, :none
    end
  end  # OptionStatic

  # strip libraries
  class OptionStrip < Option
    def self.[]
      new '-s', :linker, :none
    end
  end  # OptionStrip

  # libraries: -lpthread, -lrt, etc.
  # argument is the part after '-l'
  # NOTE: Order of these options is important
  #
  class OptionLib < Option
    def self.[]( a_param )
      raise "Missing library name" if !a_param
      p = a_param.strip
      raise "Empty library name" if p.empty?
      new '-l', :linker, :required, p
    end
  end  # OptionLib

  # library paths: -L/x/y/z
  # NOTE: Order of these options is important
  #
  class OptionLibPath < Option
    def self.[]( a_param )
      raise "Missing path" if !a_param
      p = a_param.strip
      raise "Empty path" if p.empty?
      new '-L', :linker, :required, p
    end
  end  # OptionLibPath

  # (OSX only) framework: -framework AGL|Carbon|QuickTime|OpenGL
  #
  class OptionFramework < Option
    def self.[]( a_param )
      raise "Missing framework name" if !a_param
      p = a_param.strip
      raise "Empty framework name" if p.empty?
      new '-framework', :linker, :required, p, nil, ' '
    end
  end  # OptionFramework

  # (OSX only) install_name: -install_name /opt/foo/lib/libbaz.2.dylib
  #
  class OptionInstallName < Option
    def self.[]( a_param )
      raise "Missing install name" if !a_param
      p = a_param.strip
      raise "Empty install name" if p.empty?
      new '-install_name', :linker, :required, p, nil, ' '
    end
  end  # OptionInstallName

  # (OSX only) compatibility_version: -compatibility_version 3
  #
  class OptionCompatVersion < Option
    def self.[]( a_param )
      raise "Missing compatibility version" if !a_param
      p = a_param.strip
      raise "Empty compatibility version" if p.empty?
      new '-compatibility_version', :linker, :required, p, nil, ' '
    end
  end  # OptionCompatVersion

  # (OSX only) current version: -current_version 3.0
  #
  class OptionCurrentVersion < Option
    def self.[]( a_param )
      raise "Missing current version" if !a_param
      p = a_param.strip
      raise "Empty current version" if p.empty?
      new '-current_version', :linker, :required, p, nil, ' '
    end
  end  # OptionCurrentVersion

  # Special case of linker pass-through. This is a pair of options specifying the rpath:
  #   -Wl,-rpath -Wl,/opt/foo/lib
  # Could be specified as a single argument like this: -Wl,-rpath,/opt/foo/lib
  # but we don't do this since it may cause problems with pkg-config
  #
  class OptionRPath < Option
    def self.[]( a_param )    # argument is the actual path
      raise "Missing rpath" if !a_param
      p = a_param.strip
      raise "Empty rpath" if p.empty?
      new '-Wl,', :linker, :required, p
    end

    def to_s    # convert to string
      '-Wl,-rpath ' + super
    end  # to_s
  end  # OptionRPath

  # Special case of linker pass-through. This is a pair of options for the soname:
  #   -Wl,-soname -Wl,libFoo.so
  # Could be specified as a single argument like this: -Wl,-soname,libFoo.so
  # but we don't do this since it may cause problems with pkgconfig
  #
  class OptionSOName < Option
    def self.[]( a_param )
      raise "Missing soname" if !a_param
      p = a_param.strip
      raise "Empty soname" if p.empty?
      new '-Wl,', :linker, :required, p
    end

    def to_s    # convert to string
      '-Wl,-soname ' + super
    end  # to_s
  end  # OptionSOName

  # Linker pass-through options other than rpath and soname.
  # argument is string following '-Wl,'
  # NOTE: Order of these options may be important
  #
  class OptionLinkerPassthru < Option
    def self.[]( a_param )
      raise "Missing linker option" if !a_param
      p = a_param.strip
      raise "Empty linker option" if p.empty?
      raise "-rpath should use OptionRPath" if '-rpath' == p
      raise "-soname should use OptionSOName" if '-soname' == p
      new '-Wl,', :linker, :required, p
    end
  end  # OptionLinkerPassThru

  # --------------------------------------------------
  # Linker-only options -- END
  # --------------------------------------------------

  # base class for a set of related options such as pre-processor, compiler etc.
  #
  class OptionSet
    DIAG = 'diagnostics-show-option'
    OPTIMIZE_VALUES = Set[ '1', '2', '3', 's', 'fast' ]  # -O suffixes

    # options -- array of options in this set
    # bld -- item from Build::BUILD_TYPES
    #
    attr :options, :bld

    def initialize a_bld
      raise "Bad build type: #{a_bld}" if !Build::BUILD_TYPES.include? a_bld
      @bld = a_bld
      # use an array since order is important for some options (e.g. -I, -L, etc.)
      @options = []
    end  # initialize

    # When options are changed on a per-target basis, we need to duplicate option sets.
    #
    def initialize_copy( orig )
      @options = @options.map( &:dup )    # assumes each option can be duplicated
      # @bld is a symbol so no need to clone
    end  # initialize_copy

    # helper routines to return index of given option if it is present, or nil if absent
    # override in derived classes should not be needed
    #
    def get_opt name, param = nil
      return @options.index{ |opt|    # no need to compare all fields
        opt.name == name && opt.param == param
      }
    end  # get_opt

    # Add single option after error checking; argument is an Option object
    # if option is already present in set, 'replace' determines the action: if true,
    # nothing happens; if false an exception is raised
    # Return index if option is already present, nil if it was added
    #
    # Override in derived classes to do more elaborate checking for conflicting options.
    #
    def add_opt opt, replace = false
      raise "Argument not an Option: #{opt.class.name} (#{opt.to_s})" if !opt.is_a? Option

      # check for exact match
      idx = get_opt opt.name, opt.param
      if idx
        msg = "%s already present at position %d" % [opt.to_s, idx]
        raise msg if !replace
        Build.logger.warn msg
        return idx
      end
      @options << opt
      nil
    end  # add_opt

    # add array of option strings
    def add slist, replace = false
      list = parse slist    # convert option strings to option objects
      list.each { |opt| add_opt opt, replace }
      return self
    end  # add

    # remove option from @options or @options_post according as pre is true or not
    # (pre=false only happens for linker options)
    # first argument is an Option object; return deleted option if found;
    # otherwise,
    # -- raise exception if err is true
    # -- return nil if err is false
    #
    def del opt, err = true, pre = true
      raise "Argument not an Option: #{opt.class.name}" if !opt.is_a? Option
      raise "err must be true or false" if ![true, false].include? err
      raise "pre must be true or false" if ![true, false].include? pre

      # check for exact match
      if pre
        idx = get_opt opt.name, opt.param
        return @options.delete_at( idx ) if idx    # found
      else    # linker option
        raise "Argument not a linker option" if opt.option_kind != :linker
        idx = get_post opt.name, opt.param
        return @options_post.delete_at( idx ) if idx    # found
      end
      if err
        dump
        raise "Option '%s%s' not found in #{self.class.name}" % [opt.name, opt.param]
      end
      return nil
    end  # del

    # delete list of options; slist is an array option strings
    # if err is true an exception is raised if the option is not found
    #
    def delete slist, err = true
      list = parse slist
      list.each { |opt| del opt, err }
      return self
    end  # delete

    def to_s
      @options.join ' '
    end  # to_s

    # comparing option sets -- used for example when we want to compare the set read
    # from the persistence DB with the current set
    #
    def hash
      instance_variables.inject( 17 ) { |m, v| 37 * m + instance_variable_get( v ).hash }
    end  # hash

    def == other
      return false if self.class != other.class || self.hash != other.hash
      idx = instance_variables.index { |v|
        instance_variable_get( v ) != other.instance_variable_get( v )
      }
      return idx.nil?
    end  # ==

    def eql? other
      self == other
    end  # eql?

    def dump    # debug -- print as readable list
      hdr = case self.class.name
            when /::OptionSetCPP$/o          then 'Pre-processor options'
            when /::OptionSetCC$/o           then 'C compiler options'
            when /::OptionSetCXX$/o          then 'C++ compiler options'
            when /::OptionSetAS$/o           then 'Assembler options'
            when /::OptionSetLinkCCLib$/o    then 'Linker options (C library)'
            when /::OptionSetLinkCXXLib$/o   then 'Linker options (C++ library)'
            when /::OptionSetLinkCCExec$/o   then 'Linker options (C executable)'
            when /::OptionSetLinkCXXExec$/o  then 'Linker options (C++ executable)'
            else raise "Bad option set name: #{self.class.name}"
            end  # case
      # one per line, with some indent
      msg = @options.inject( "#{hdr}:\n" ) { |m,v| m + sprintf( "  %s\n", v ) }
      msg += "  build type = %s\n" % @bld
      LogMain.get.debug msg
    end  # dump

  end  # OptionSet

  # pre-processor options
  class OptionSetCPP < OptionSet

    def parse slist    # parse array of option strings and return list of objects
      result = []
      slist.each { |opt|
        case opt
        when /^-D(\S+)/o then result << OptionDefine[ '-D', $1 ]
        when /^-U(\S+)/o then result << OptionDefine[ '-U', $1 ]
        when /^-I(\S+)/o then result << OptionInclude[ $1 ]
        else raise "Bad pre-processor option: #{opt}"
        end
      }
      return result
    end  # parse

    # helper routine to add option after error checking; argument is an Option object
    def add_opt opt, replace = false
      return if super    # already present

      # exact match for new option not present so it was added at the end

      # -D, -U and -I all need a parameter
      raise "Pre-processor option %s missing parameter" % opt.name if !opt.param

      # check for conflicting -U/-D flags
      log = Build.logger
      if ['-D', '-U'].include?( opt.name )
        neg = '-D' == opt.name ? '-U' : '-D'    # negated form
        idx = @options.index{ |v| v.name == neg && v.param == opt.param }
        if idx
          old = @options[ idx ]
          raise "Existing %s conflicts with %s" % [old.to_s, opt.to_s] if !replace

          # remove new option from end where it was just added, and replace existing
          # option with it
          #
          @options.pop
          @options[ idx ] = opt
          log.warn "Replaced %s with %s" % [old.to_s, opt.to_s]
          return
        end

        # no conflicting options, nothing more to do
        return
      end  # -D/-U check

      raise "Bad pre-processor option: %s" % opt.name if '-I' != opt.name

      # add more checks as needed
    end  # add_opt

    # override OptionSet.{add,del} if needed

  end  # OptionSetCPP

  class OptionSetCLike < OptionSet    # base for C and C++

    # Since C and C++ share a lot of common options, they are processed here; options
    # specific to those languages should be handled in the subclass overrides.
    #
    def parse slist    # parse array of option strings and return list of objects
      log = Build.logger
      log.debug "Parsing C/C++ options ..."

      result = []
      slist.each { |opt|
        case opt
        when /^-m(\S+)/o
          name = $1
          result << OptionMachine[ name ]

        when /^-f(\S+)/o
          name = $1
          case name
          when DIAG then result << OptionDiagnostic[ DIAG ]
          when 'PIC' then result << OptionPIC[ :compiler ]
          when 'signed-char' then result << OptionSignedChar[]
          when 'unsigned-char' then result << OptionUnsignedChar[]
          when 'no-common' then result << OptionNoCommon[]
          when 'no-strict-aliasing', 'inline-functions'
            raise "Optimization option -f%s in debug build" % name if :dbg == @bld
            result << OptionOptimize[ '-f', name ]
          else raise "Unknown -f option: #{name}"
          end

        when /^--param ([-=a-zA-Z0-9]+)/o
          val = $1
          raise "Optimization option --param %s in debug build" % name if :dbg == @bld
          result << OptionOptimizeParam[ val ]

          # add support for other variants if needed
        when /^-std=gnu99/o then result << OptionStd[ 'gnu99' ]

        when /^-std=c99/o then result << OptionStd[ 'c99' ]

        when /^-W(\S+)/o then
          if $1 == 'a,--noexecstack'    # assembler pass through
            result << OptionNoExecStack[]
          else
            result << OptionWarning[ $1 ]
          end

        when /^-g$/o
          raise "-g option invalid for release build" if :rel == @bld
          result << OptionDebug[]

        when /^-s$/o
          raise "-s option valid only for release build" if :rel != @bld
          result << OptionStrip[]

        when /^-O(\S+)$/o
          level = $1
          raise "Unknown -O level: #{level}" if !OPTIMIZE_VALUES.include? level
          raise "-O%s option not valid for debug build" % level if
            :dbg == @bld && '0' != level
          raise "-O0 option not valid for release build" if
            :rel == @bld && '0' == level
          # allow optimization off in optimized builds
          result << OptionOptimize[ '-O', level ]

        when /^-(?:D|U|I)(?:\S+)$/o
          raise "%s should be added as a pre-processor option" % opt

        when /^-Wl,(?:\S+)$/o, /-(?:static|dynamic)/o, /-L(?:\S+)/o
          raise "%s should be added as a linker option" % opt

        else raise "Bad compiler option: #{opt}"
        end  # case
      }
      log.debug "... done parsing C/C++ options"
      return result
    end  # parse

    # helper routine to add option after error checking; argument is an Option object
    # need overrides in derived classes since checks will depend on the kind of option
    #
    def add_opt opt, replace = false
      return if super    # already present

      # exact match for new option not present so it was added at the end
      log = Build.logger
      if '-O' == opt.name      # check for conflicting -O flags
        # we insist on a parameter
        raise "-O needs a parameter" if !opt.param

        # if -O was not already present, nothing more to do
        idx = @options[0...-1].index{ |v| v.name == '-O' }
        return if !idx

        # -O is already present
        old = @options[ idx ]
        raise "Existing %s conflicts with %s" % [old.to_s, opt.to_s] if !replace

        # remove new option from end where it was just added, and replace existing
        # option with it
        #
        @options.pop
        @options[ idx ] = opt
        log.warn "Replaced %s with %s" % [old.to_s, opt.to_s]
        return
      end

      return if !opt.param    # no parameter, so literal option; nothing more to do

      # have a parameter; check for negated forms (this is for options like
      # -f[no-]keep-inline-functions)

      # remove negation if present, add if absent
      p = opt.param.sub( /^no-/o, '' )
      p = ('no-' + opt.param) if p.size == opt.param.size
      idx = get_opt opt.name, p
      if idx
        old = @options[ idx ]
        raise "Negated %s already present at position %s: %s" %
          [opt.to_s, idx, old.to_s] if !replace

        # remove new option from end where it was just added, and replace existing
        # (negated) option with it
        #
        @options.pop
        @options[ idx ] = opt
        log.warn "Replaced %s with %s" [old.to_s, opt.to_s]
        return
      end

      # add more checks as needed, e.g.
      #   * -msse2 and other optimizations may not be meaningful if optimization is
      #     not enabled (-O absent or -O0 present)
      #
    end  # add_opt

    # override OptionSet.{add,del} if needed

  end  # OptionSetCLike

  # C compiler options
  class OptionSetCC < OptionSetCLike
  end  # OptionSetCC

  # C++ compiler options
  class OptionSetCXX < OptionSetCLike
  end  # OptionSetCXX

  # Linker options (base class for linking C and C++ objects)
  class OptionSetLink < OptionSet

    # options that come after the object file list; so the options on the link command
    # will have the form: <@options> <object-files> <@options_post>
    #
    attr :options_post

    def initialize a_bld
      super
      @options_post = []
    end

    # When options are changed on a per-target basis, we need to duplicate option sets.
    #
    def initialize_copy( orig )
      # these assume each option can be duplicated properly
      @options = @options.map( &:dup )
      @options_post = @options_post.map( &:dup )
      # @bld is a symbol so no need to clone
    end  # initialize_copy

    def get_post name, param = nil    # get index of option in post list
      return @options_post.index{ |opt|
        opt.name == name && opt.param == param
      }
    end  # get_post

    # parse an array of strings each being a linker option and return pair of lists of
    # option objects for the pre and post sets
    #
    def parse slist
      # For the '-Wl,' options that come in pairs, we record the state here; values:
      #   :need_rpath -- need actual path for rpath
      #   :need_soname -- need actual soname
      #
      state = nil
      pre, post = [], []
      slist.each { |opt|
        case opt

        when /\A-framework\s+(\S+)/o    # OSX specific (should precede -f below)
          name = $1
          raise "Option -framework only for OSX" if !Build.system.darwin?
          if !state.nil?
            raise "Expecting rpath path, got -framework" if :need_rpath == state
            raise "Expecting soname name, got -framework" if :need_soname == state
          end
          # this option may also be present when linking an executable
          post << OptionFramework[ name ]

        when /\A-f(\S+)/o
          name = $1
          if !state.nil?
            raise "Expecting rpath path, got -f#{name}" if :need_rpath == state
            raise "Expecting soname name, got -f#{name}" if :need_soname == state
          end
          case name
          when 'PIC' then pre << OptionPIC[ :linker ]
          when 'lto' then pre << OptionLTO[ :linker ]
          else raise "Bad linker option: #{opt}"
          end  # case

        when /\A-m32\Z/o
          pre << OptionMachine[ '32', :linker ]

        when /\A-nostdlib\Z/o
          if !state.nil?
            raise "Expecting rpath path, got -nostdlib" if :need_rpath == state
            raise "Expecting soname name, got -nostdlib" if :need_soname == state
          end
          pre << OptionNoStdLib[]

        when '-DPIC'
          raise "-DPIC is a pre-processor option not meaningful to the linker"

        when /\A-shared\Z/o
          if !state.nil?
            raise "Expecting rpath path, got -shared" if :need_rpath == state
            raise "Expecting soname name, got -shared" if :need_soname == state
          end

          # this option should not be present when linking an executable; otherwise, the
          # link will appear to succeed but all attempts to run the executable will fail
          # since it is a shared library
          #
          raise "-shared not valid for executable" if
            self.is_a?( OptionSetLinkCCExec ) || self.is_a?( OptionSetLinkCXXExec )
          pre << OptionShared[]

        when /^-dynamiclib/o    # OSX specific
          raise "Option -dynamiclib only for OSX" if !Build.system.darwin?
          if !state.nil?
            raise "Expecting rpath path, got -dynamiclib" if :need_rpath == state
            raise "Expecting soname name, got -dynamiclib" if :need_soname == state
          end

          # this option should not be present when linking an executable; otherwise, the
          # link will appear to succeed but all attempts to run the executable will fail
          # since it is a shared library -- check this in the target
          #
          raise "-dynamiclib not valid for executable" if
            self.is_a?( OptionSetLinkCCExec ) || self.is_a?( OptionSetLinkCXXExec )
          pre << OptionDynamicLib[]

        when /^-install_name\s+(\S+)/o    # OSX specific
          name = $1
          raise "Option -install_name only for OSX" if !Build.system.darwin?
          if !state.nil?
            raise "Expecting rpath path, got -install_name" if :need_rpath == state
            raise "Expecting soname name, got -install_name" if :need_soname == state
          end

          # this option should not be present when linking an executable; not clear what
          # OSX does, check later
          #
          raise "-install_name not valid for executable" if
            self.is_a?( OptionSetLinkCCExec ) || self.is_a?( OptionSetLinkCXXExec )
          pre << OptionInstallName[ name ]

        when /^-compatibility_version\s+(\S+)/o    # OSX specific
          cversion = $1
          raise "Option -compatibility_version only for OSX" if !Build.system.darwin?
          if !state.nil?
            raise "Expecting rpath path, got -compatibility_version" if
              :need_rpath == state
            raise "Expecting soname name, got -compatibility_version" if
              :need_soname == state
          end
          raise "-compatibility_version not valid for executable" if
            self.is_a?( OptionSetLinkCCExec ) || self.is_a?( OptionSetLinkCXXExec )
          pre << OptionCompatVersion[ cversion ]

        when /^-current_version\s+(\S+)/o    # OSX specific
          cversion = $1
          raise "Option -current_version only for OSX" if !Build.system.darwin?
          if !state.nil?
            raise "Expecting rpath path, got -current_version" if
              :need_rpath == state
            raise "Expecting soname name, got -current_version" if
              :need_soname == state
          end
          raise "-current_version not valid for executable" if
            self.is_a?( OptionSetLinkCCExec ) || self.is_a?( OptionSetLinkCXXExec )
          pre << OptionCurrentVersion[ cversion ]

        when /^-O(\S+)/o    # -O options (link time optimization)
          level = $1
          if !state.nil?
            raise "Expecting rpath path, got -O#{level}" if :need_rpath == state
            raise "Expecting soname name, got -O#{level}" if :need_soname == state
          end
          pre << OptionOptimize[ '-O', level, :linker ]

        when /^-L(\S+)/o    # -L options (library paths)
          p = $1
          if !state.nil?
            raise "Expecting rpath path, got -L#{p}" if :need_rpath == state
            raise "Expecting soname name, got -L#{p}" if :need_soname == state
          end
          post << OptionLibPath[ p ]

        when /^-l(\S+)/o    # -l options (library files)
          lib = $1
          if !state.nil?
            raise "Expecting rpath path, got -l#{lib}" if :need_rpath == state
            raise "Expecting soname name, got -l#{lib}" if :need_soname == state
          end
          post << OptionLib[ lib ]

        when /^-Wl,(\S+)/o    # -Wl, options (passed to linker)
          name = $1
          
          if '-rpath' == name    # next option is actual path
            if !state.nil?
              raise "Expecting rpath path, got -rpath" if :need_rpath == state
              raise "Expecting soname name, got -rpath" if :need_soname == state
              raise "Unexpected state: #{state}"
            end
            state = :need_rpath
          elsif '-soname' == name
            if !state.nil?
              raise "Expecting rpath path, got -soname" if :need_rpath == state
              raise "Expecting soname name, got -soname" if :need_soname == state
              raise "Unexpected state: #{state}"
            end
            state = :need_soname
          else
            case state
            when nil then post << OptionLinkerPassthru[ name ]
            when :need_rpath then post << OptionRPath[ name ]
            when :need_soname then post << OptionSOName[ name ]
            else raise "Unexpected state: #{state}"
            end
            state = nil
          end

        else raise "Bad linker option: #{opt}"
        end  # case
      }
      return [pre, post]
    end  # parse

    # for linker options, we have 2 routines: add_opt and add_post to add to @options
    # and @options_post respectively

    # helper routine to add option after error checking; argument is an Option object
    def add_opt opt, replace = false
      raise "Argument not a linker option" if opt.option_kind != :linker
      return if super    # already present

      # exact match for new option not present so it was added at the end
      case opt.name
      when /-O/, /-m/, /-install_name/, /-compatibility_version/, /-current_version/ then

        # check for conflicting values (omit last position since the option currently
        # resides there
        #
        idx = @options[ 0 ... -1 ].index{ |v| v.name == opt.name }
        return if !idx    # not present, so leave new option where it is

        # option is already present
        old = @options[ idx ]
        raise "Existing %s [%d] conflicts with %s [%d]" %
          [old.to_s, idx, opt.to_s, @options.size - 1] if !replace

        log = Build.logger
        # remove new option from end where it was just added, and replace existing
        # option with it
        #
        @options.pop
        @options[ idx ] = opt
        log.warn "Replaced %s with %s" % [old.to_s, opt.to_s]

      else

        # exact match not present; if there are no parameters, nothing more to do (e.g.
        # such as -static, -dynamic, -fPIC, -flto)
        #
        return if !opt.param
        raise "Unsupported linker option: %s%s" % [opt.name, opt.param]
      end  # case
    end  # add_opt

    # helper routine to add option to post list after error checking; argument is an
    # Option object
    #
    def add_post opt, replace = false
      raise "Argument not an Option: #{opt.class.name}" if !opt.is_a? Option
      raise "Argument not a linker option" if opt.option_kind != :linker

      # check for exact match
      idx = get_post opt.name, opt.param
      if idx
        msg = "%s already present at position %d" % [opt.to_s, idx]
        raise msg if !replace
        Build.logger.warn msg
        return
      end

      # exact match not present; The only options we handle here are:
      #   -L/foo/bar
      #   -lxyz
      #   -Wl,...
      # all of which need parameters, so if there are no parameters, this is an error
      #
      raise "Bad linker (post) option: %s" % opt.name if !opt.param

      @options_post << opt
    end  # add_post

    # add array of options (each is an option string)
    # if replace is true any conflicting existing options are
    # removed; if false, such conflicting options raise an exception
    #
    def add slist, replace = false
      pre, post = parse slist
      # check pre and post for conflicts within -- do later
      pre.each  { |opt| add_opt opt, replace }
      post.each { |opt| add_post opt, replace }
    end  # add

    # delete array of options (each is an option string);
    # if err is true an exception is raised if the option is not found
    #
    def delete slist, err = true
      # check pre and post for conflicts within -- do later
      pre, post = parse slist
      pre.each  { |opt| del opt, err }
      post.each { |opt| del opt, err, false }
    end  # delete

    # These two routines are used to generate the final linker command
    def to_s
      @options.join ' '
    end  # to_s
    def post_to_s
      @options_post.join ' '    # @options_post is never nil
    end  # post_to_s

    def dump    # debug
      super
      if ! @options_post.empty?
        msg = @options_post.inject( "(post):\n" ) { |m,v| m + sprintf( "  %s\n", v ) }
        LogMain.get.debug msg
      end
    end  # dump

  end  # OptionSetLink

  # Linker options for library (C)
  class OptionSetLinkCCLib < OptionSetLink
    # customize later if necessary
  end  # OptionSetLinkCCLib

  # Linker options for library (C++)
  class OptionSetLinkCXXLib < OptionSetLink
    # customize later if necessary
  end  # OptionSetLinkCXXLib

  # Linker options for executable (C)
  class OptionSetLinkCCExec < OptionSetLink
    # customize later if necessary
  end  # OptionSetLinkCCExec

  # Linker options for executable (C++)
  class OptionSetLinkCXXExec < OptionSetLink
    # customize later if necessary
  end  # OptionSetLinkCXXExec

  # Assembler options
  # GCC runs only the assembler ('as') on .s files but both pre-processor and assembler
  # on .S files except on the Mac where it is rumored to run both on both files (need to
  # verify)
  # Currently we don't have .s files so we assume all preprocessor flags are meaningful
  # and usable when assembling
  #
  class OptionSetAS < OptionSet

    def parse slist    # parse array of option strings and return list of objects
      # assembler options: We currently use no assembler options; the only ones that
      # are potentially useful are the -g, -I, -D and -U preprocessor options
      #
      # Not clear if this is used by the assembler -- check later:
      #   -flto  -- link time optimization; needs to be used at both compile time and
      #             link time
      #
      result = []
      slist.each { |opt|
        case opt
        when /^-g$/o
          result << OptionDebug[ :assembler ]
        when /^-m32$/o
          result << OptionMachine[ '32', :assembler ]

        else raise "Assembler option %s not supported" % opt
        end  # case
      }
      return result
    end  # parse

    # helper routine to add option after error checking; argument is an Option object
    # need overrides in derived classes since checks will depend on the kind of option
    #
    def add_opt opt, replace = false
      raise "-g option invalid for release build" if
        :rel == @bld && opt.is_a?( OptionDebug )
      super
    end  # add_opt

    # override OptionSet.{add,del} if needed

  end  # OptionSetAS

  class OptionGroup
    # kinds of processor (we use different options when linking C and C++ objects)
    PROC_KINDS = Set[:cpp, :cc, :cxx, :as, :ld_cc_lib, :ld_cxx_lib, :ld_cc_exec,
                     :ld_cxx_exec]

    # options is a hash, each value of which is an OptionSet
    # options[:as]  -- assembler options for .S files
    # options[:cpp]  -- pre-processor options
    # options[:cc]   -- C compiler options
    # options[:cxx]  -- C++ compiler options
    # options[:ld_cc_lib]   -- linker options for C files (library)
    # options[:ld_cc_exec]  -- linker options for C files (executable)
    # options[:ld_cxx_lib]  -- linker options for C++ files (library)
    # options[:ld_cxx_exec] -- linker options for C++ files (executable)
    # bld_type -- :dbg, :opt, :rel
    #
    attr :options
    attr :build_type

    def initialize a_bld
      raise "Bad build type: #{a_bld}" if !Build::BUILD_TYPES.include? a_bld
      @build_type = a_bld

      @options = { :as     => OptionSetAS.new( a_bld ),
                   :cpp    => OptionSetCPP.new( a_bld ),
                   :cc     => OptionSetCC.new( a_bld ),
                   :cxx    => OptionSetCXX.new( a_bld ),
                   :ld_cc_lib   => OptionSetLinkCCLib.new( a_bld ),
                   :ld_cxx_lib  => OptionSetLinkCXXLib.new( a_bld ),
                   :ld_cc_exec  => OptionSetLinkCCExec.new( a_bld ),
                   :ld_cxx_exec => OptionSetLinkCXXExec.new( a_bld ) }

    end  # initialize

    # sample usage:
    #     add( ['-I/opt/foo/include'],             :cpp )
    #     add( ['-Wshadow, -O3'],                  :cxx )
    #     add( ['-Wl,-rpath', '-Wl,/opt/foo/lib'], :ld_cc_lib )
    #
    # 'slist' is an array of option strings
    # 'replace' determines what happens if a conflicting option already exists
    # (e.g. -DFOO, -UFOO): if true, the conflicting optiion is replaced; otherwise an
    # exception is raised
    #
    def add slist, kind, replace = false
      raise "Bad kind: #{kind}" if !PROC_KINDS.include? kind
      raise "Missing option list" if !slist || slist.empty?
      @options[ kind ].add slist, replace
    end  # add

    # sample usage:
    #     delete( ['-I/opt/foo/include'],             :cpp )
    #     delete( ['-Wshadow', '-O3'],                        :cxx )
    #     delete( ['-Wl,-rpath', '-Wl,/opt/foo/lib'], :ld_cc_lib )
    #
    # 'slist' is an array of option strings
    # err determines what happens if an option is not found: if true an exception is
    # raised, otherwise, a warning is logged
    #
    def delete slist, kind, err = true
      raise "Bad kind: #{kind}" if !PROC_KINDS.include? kind
      raise "Missing option list" if !slist || slist.empty?
      @options[ kind ].delete slist, err
    end  # delete

    def dump    # debug
      LogMain.get.debug "OptionGroup: bld_type = #{@build_type}"
      @options.each{ |_, val| val.dump }
    end  # dump

  end  # OptionGroup

  # Delete list of options from global default set; intended to be a user-facing function
  # slist -- array of option strings
  # kind -- a symbol from OptionGroup::PROC_KINDS indicating the kind of options
  # err -- if true, an option not found in the global list will trigger an exception
  #        if false, such an option will be ignored
  #
  def delete_options slist, kind, err = true
    raise "@options not yet initialized (call setup to do that)" if
      !defined? @options
    @options.delete slist, kind, err
  end  # delete_options

  # Add list of options to global default set; intended to be a user-facing function
  # slist -- array of option strings
  # kind -- a symbol from PROC_KINDS indicating the kind of options
  #
  def add_options slist, kind, replace = false
    raise "@options not yet initialized (call setup to do that)" if
      !defined? @options
    @options.add slist, kind, replace
  end  # add_options
end  # Build

# unit test
if $0 == __FILE__
  # initialize logger
  Build::LogMain.set_log_file_params( :name => 'opt.log' )

  # various items in Build defined in build.rb need to be replicated here
  # BUILD_TYPES, logger
  #
  Build.const_set( 'BUILD_TYPES', Set[ :dbg, :rel, :opt ] ) if !defined? Build::BUILD_TYPES

  if !Build.respond_to? :logger
    Build.define_singleton_method( :logger ) do
      Build::LogMain.get
    end
  end

  # debug build options
  grp_d = Build::OptionGroup.new :dbg
  cpp_list = ['-UNDEBUG', '-UENCAPSULATION_IS_GOOD', '-DPIC',
              '-I/opt/foo/include']
  grp_d.add cpp_list, :cpp
  cc_list = ['-g']
  grp_d.add cc_list, :cc
  cxx_list = ['-g']
  grp_d.add cxx_list, :cxx

  # optimized build options
  grp_o = Build::OptionGroup.new :opt
  cpp_list = ['-UNDEBUG', '-DENCAPSULATION_IS_GOOD', '-DPIC',
              '-I/opt/foo/include']
  grp_o.add cpp_list, :cpp
  cc_list = ['-g', '-O2', '-fno-strict-aliasing', '-finline-functions',
             '--param max-inline-insns-single=1800']
  grp_o.add cc_list, :cc
  cxx_list = ['-g', '-O2', '-fno-strict-aliasing', '-finline-functions',
             '--param max-inline-insns-single=1800']
  grp_o.add cxx_list, :cxx

  # release build options
  grp_r = Build::OptionGroup.new :rel
  [grp_d, grp_o, grp_r].map( &:dump )

  # test marshal/unmarshal
  cpp1 = grp_d.options[ :cpp ]
  s = Marshal.dump cpp1; puts "Marshal size = %d" % s.size
  cpp2 = Marshal.load s
  if cpp1 != cpp2
    printf( "Comparison: false\nClasses: %s, %s\nhashes = %d, %d\n" +
            "No. of elements: %d, %d\n",
            cpp1.class.name, cpp2.class.name, cpp1.hash, cpp2.hash,
            cpp1.options.size, cpp2.options.size )
    cpp1.dump
    cpp2.dump
  end

  ld_list = ['-g', '-Wl,-no-undefined', '-L/opt/foo/lib']
  grp_d.add ld_list, :ld_cc_exec
  opt1 = grp_d.options[ :ld_cc_exec ]
  s = Marshal.dump opt1; puts "Marshal size = %d" % s.size
  opt2 = Marshal.load s
  if opt1 != opt2
    printf( "Comparison: false\nClasses: %s, %s\nhashes = %d, %d\n" +
            "No. of elements: %d, %d\n",
            opt1.class.name, opt2.class.name, opt1.hash, opt2.hash,
            opt1.options.size, opt2.options.size )
    opt1.dump
    opt2.dump
  end

end
