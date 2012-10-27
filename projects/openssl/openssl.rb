# Ruby-based build system.
# Author: ram

c = File.expand_path( File.dirname __FILE__ )      # this dir
m = File.expand_path( File.join c, '..', '..' )    # main dir
[ c, m ].each { |p| $LOAD_PATH.unshift p unless $LOAD_PATH.include? p }

%w{ build options targets openssl_config.rb features }.each{ |f| require f }

# Individual bundles of libraries and/or executables specified -- one class per bundle
#
class Build

  # Base class for a new subproject -- MUST be extended by each bundle
  #
  # Each collection of closely related libraries and/or executables whose sources appear
  # under a single directory is called a bundle. Each bundle is configured via a single
  # derived class of Bundle.
  #
  # Each derived class of Bundle _must_ have:
  # (a) an initialize method that takes a single argument (current build object).
  # (b) a setup method that sets up everything needed by the bundle.
  # The base class has additional methods to simplify this work but derived classes may
  # ignore these methods if they so choose.
  #
  # These are singleton classes used for encapsulating all the information about a single
  # bundle, namely:
  # A. The root directory where sources for this bundle are located.
  # B. The set of libraries and executables that must be built for this bundle.
  # C. The set of object files that comprise each library or executable.
  # D. Any additions or deletions to the compiler and linker options for any object,
  #    library, or executable in this bundle.
  #
  # The setup method must do these things:
  # 1. Define @dir_root relative to src_root (e.g. 'libFoo')
  # 2. Create any needed directories under obj_root
  # 3. Invoke build.discover_targets with suitable include/exclude lists
  # 4. Invoke build.add_targets to add all the library and executable targets.
  # 5. Invoke build.add_default_targets to add all the library and executable targets that
  #    should be built by default
  # 6. Invoke build.delete_target_options and build.add_target_options to adjust the
  #    compiler and linker options for targets in this bundle, if necessary.
  #
  class Bundle
    attr :build, :dir_root, :include, :exclude

    # derived class overrides should call 'super', then initialize these instance
    # variables and any others they might need
    #
    # dir_root    -- [required] root directory relative to build.src_root (e.g 'libFoo')
    # include     -- [optional] subdirectories to include in search for source files
    # exclude     -- [optional] subdirectories to exclude in search for source files
    # libraries   -- [optional] list of libraries
    # executables -- [optional] list of executables
    # targets     -- [optional] list of default targets
    #
    def initialize b
      @build = b
    end  # initialize

    def discover_targets
      # find targets automatically; exclude and include lists are relative to src_root
      incl = if ! defined? @include
               [@dir_root]
             elsif '.' == @dir_root
               @include
             else
               @include.map!{ |f| File.join( @dir_root, f ) }
             end
      excl = if ! defined? @exclude
               nil
             elsif '.' == @dir_root
               @exclude
             else
               @exclude.map!{ |f| File.join( @dir_root, f ) }
             end

      @build.discover_targets :include => incl, :exclude => excl
    end  # discover_targets

    def add_lib_targets    # add library targets and their dependencies
      if !defined?( @libraries ) || @libraries.nil? || @libraries.empty?
        Build.logger.warn "No libraries in %s" % self.class.name
        return
      end

      # Add each library target to the global list as it is created since it may need
      # to be found as a dependency for a later library
      #
      @libraries.each { |lib|
        t = @build.lib_target lib
        @build.add_targets [t]
      }
    end  # add_lib_targets

    def add_exe_targets    # add executable targets and their dependencies
      if !defined?( @executables ) || @executables.nil? || @executables.empty?
        Build.logger.warn "No executables in %s" % self.class.name
        return
      end

      # An executable cannot be a dependency of another so we can create them all and then
      # add them in one go
      #
      @build.add_targets @executables.map{ |e| @build.exe_target( e ) }
    end  # add_exe_targets

    def add_default_targets    # add any default targets
      @build.add_default_targets @targets
    end  # add_default_targets

    # create necessary directories under obj_root; by default, we create a 'static'
    # subdirectory if we are linking statically; override as needed
    #
    def create_dirs
      if :dynamic == @build.link_type
        return if '.' == @dir_root
        dir = File.join @build.obj_root, @dir_root
      else    #  static
        dir = if '.' == @dir_root
                File.join @build.obj_root, 'static'
              else
                File.join @build.obj_root, @dir_root, 'static'
              end
      end
      Util.run_cmd "mkdir -p #{dir}"
    end  # create_dirs

    def setup    # main entry point to configure this bundle
      log = Build.logger
      log.debug "Setting up %s ..." % self.class.name

      # create necessary directories under build.obj_root in derived classes

      # discover source files and create associated targets
      discover_targets

      # add library targets
      add_lib_targets

      # add executable targets
      add_exe_targets

      # customize options for individual files as needed

      # default targets to build (may be modified by customize() and later, possibly,
      # by commandline options
      #
      add_default_targets

      log.debug "... done setting up %s" % self.class.name
    end  # setup

    # Finally, add this line at the end of each derived class to register it with the
    # class variable containing all known bundles:
    #
    # Build.add_bundle self
  end  # Bundle

  # from a build perspective, libcrypto is unusual in these ways:
  #
  # + A static build creates a set of libraries that differs from the set created by a
  #   dynamic build:
  #     static --> libcrypto.a, libssl.o
  #     dynamic --> libcrypto.so,  libssl.o,       libchil.so,      libnuron.so,
  #                 libgost.so,    libpadlock.so,  libsureware.so,  libcapi.so,
  #                 libgmp.so,     libubsec.so,    libatalla.so,    libaep.so,
  #                 libcswift.so,  lib4758cca.so
  # + The static library includes files from a sibling directory 'engines'
  #
  class LibCrypto < Bundle

    # helper routine to add to exclude list
    # list of files, subdirectory, parent directory
    #
    def add_ex list, d, p = 'crypto'
      list.map!{ |f| File.join p, d, f }
      # common = @exclude & list
      # raise "Duplicates: #{common}" if ! common.empty?
      @exclude += list
    end  # add_ex

    # define exclude list
    def set_exclude    # separate function for readability since there are many files
      # exclude files from 'crypto'
      @exclude = %w{ armcap.c       LPdir_nyi.c    LPdir_unix.c
                     LPdir_vms.c    LPdir_win32.c  LPdir_win.c
                     LPdir_wince.c  mem_clr.c      o_dir_test.c
                     ppccap.c       s390xcap.c     sparcv9cap.c }
      @exclude.map!{ |f| File.join 'crypto', f }

      # no exclusions in these subdirectories:
      #   objects seed modes dso buffer stack err asn1 pem x509 txt_db pkcs12 comp ocsp ui
      #   krb5 cms ts cmac

      # the code below is just a compact way of getting a list like this:
      #   @exclude = [ md4/md4.c, md4/md4test.c, md5/md5.c,  md5/md5test.c, ... ]
      #
      ex = []
      ex << %w{ md4.c  md4test.c };                                    ex << 'md4'
      ex << %w{ md5.c  md5test.c };                                    ex << 'md5'
      ex << %w{ sha1.c     sha.c      sha1test.c
                shatest.c  sha256t.c  sha512t.c };                     ex << 'sha'
      ex << %w{ mdc2test.c };                                          ex << 'mdc2'
      ex << %w{ hmactest.c };                                          ex << 'hmac'
      ex << %w{ rmd160.c rmdtest.c };                                  ex << 'ripemd'
      ex << %w{ wp_test.c };                                           ex << 'whrlpool'
      ex << %w{ cbc3_enc.c  des_opts.c  des.c       destest.c
                speed.c     read_pwd.c  ncbc_enc.c  rpw.c };           ex << 'des'
      ex << %w{ aes_cbc.c  aes_core.c  aes_x86core.c };                ex << 'aes'
      ex << %w{ rc2test.c  rc2speed.c  tab.c };                        ex << 'rc2'
      ex << %w{ rc4.c  rc4_enc.c  rc4_skey.c  rc4speed.c  rc4test.c }; ex << 'rc4'
      ex << %w{ idea_spd.c ideatest.c };                               ex << 'idea'
      ex << %w{ bf_cbc.c  bf_opts.c  bfspeed.c  bftest.c };            ex << 'bf'
      ex << %w{ castopts.c  cast_spd.c  casttest.c };                  ex << 'cast'
      ex << %w{ camellia.c  cmll_cbc.c };                              ex << 'camellia'
      ex << %w{ divtest.c   bntest.c   vms-helper.c  bnspeed.c
                expspeed.c  exptest.c  bn_asm.c      exp.c };          ex << 'bn'
      ex << %w{ ectest.c };                                            ex << 'ec'
      ex << %w{ rsa_test.c };                                          ex << 'rsa'
      ex << %w{ dsagen.c  dsatest.c };                                 ex << 'dsa'
      ex << %w{ ecdsatest.c };                                         ex << 'ecdsa'
      ex << %w{ p1024.c  p512.c  dhtest.c  p192.c };                   ex << 'dh'
      ex << %w{ ecdhtest.c };                                          ex << 'ecdh'
      ex << %w{ enginetest.c };                                        ex << 'engine'
      ex << %w{ bf_lbuf.c  bss_rtcp.c };                               ex << 'bio'
      ex << %w{ lh_test.c };                                           ex << 'lhash'
      ex << %w{ rand_vms.c  randtest.c };                              ex << 'rand'
      ex << %w{ e_dsa.c   evp_test.c  openbsd_hw.c };                  ex << 'evp'
      ex << %w{ v3prin.c  v3conf.c    tabtest.c };                     ex << 'x509v3'
      ex << %w{ cnf_save.c  test.c };                                  ex << 'conf'
      ex << %w{ verify.c    example.c  bio_ber.c  enc.c
                pk7_dgst.c  pk7_enc.c  dec.c      sign.c };            ex << 'pkcs7'
      ex << %w{ pq_test.c };                                           ex << 'pqueue'
      ex << %w{ srptest.c };                                           ex << 'srp'

      ex.each_slice( 2 ){ |list, dir| add_ex list, dir }

      # exclude files in engines/ccgost
      @exclude << File.join( 'engines', 'ccgost', 'gostsum.c' )

      # exclude directories in 'crypto'
      ex = %w{ jpake  store  rc5  threads  md2  perlasm }
      ex.map!{ |f| File.join 'crypto', f }
      @exclude += ex
    end  # set_exclude

    # define include list
    def set_include    # separate function for readability since there are many files
      # @include = %w{ aes     asn1     bf      bio    bn      buffer  camellia  cast
      #                cmac    cms      comp    conf   db      des     dh        dsa
      #                dso     ec       ecdh    ecdsa  engine  err     evp       hmac
      #                idea    krb5     lhash   md4    md5     mdc2    modes     objects
      #                ocsp    pem      pkcs12  pkcs7  pqueue  rand    rc2       rc4
      #                ripemd  rsa      seed    sha    srp     stack   txt_db    ts
      #                ui      whrlpool x509    x509v3 }    # directories
      
      @include = %w{ crypto engines include }

      # set of files in libcrypto; since this set has a large number of elements, we
      # accumulate it in per-subdirectory increments
      #
      f_base = %w{ cryptlib  cversion  cpt_err
                   ebcdic    ex_data   fips_ers
                   mem       mem_dbg   o_time
                   o_str     o_dir     o_fips
                   o_init    uid       x86_64cpuid }

      f_objects = %w{ obj_dat  obj_err  obj_lib obj_xref o_names }

      f_md4 = %w{ md4_dgst md4_one }

      f_md5 = %w{ md5_dgst md5_one md5-x86_64 }

      f_sha = %w{ sha_dgst  sha1dgst  sha_one      sha1_one
                  sha256    sha512    sha1-x86_64  sha256-x86_64  sha512-x86_64 }

      f_mdc2 = %w{ mdc2dgst mdc2_one }

      f_hmac = %w{ hmac hm_ameth hm_pmeth }

      f_ripemd = %w{ rmd_dgst rmd_one }

      f_whrlpool = %w{ wp_dgst wp-x86_64 }

      f_des = %w{ set_key   ecb_enc  cbc_enc       ecb3_enc  cfb64enc
                  cfb64ede  cfb_enc  ofb64ede      enc_read  enc_writ
                  ofb64enc  ofb_enc  str2key       pcbc_enc  qud_cksm
                  rand_key  des_enc  fcrypt_b      fcrypt    xcbc_enc
                  rpc_enc   cbc_cksm ede_cbcm_enc  des_old   des_old2
                  read2pwd }

      f_aes = %w{ aes-x86_64         aes_cfb       aes_ctr       aes_ecb
                  aes_ige            aes_misc      aes_ofb       aes_wrap
                  aesni-sha1-x86_64  aesni-x86_64  bsaes-x86_64  vpaes-x86_64 }

      f_rc2     = %w{ rc2_ecb rc2_skey rc2_cbc rc2cfb64 rc2ofb64 }

      f_rc4     = %w{ rc4-x86_64 rc4-md5-x86_64 rc4_utl }

      f_idea    = %w{ i_cbc i_cfb64 i_ofb64 i_ecb i_skey }

      f_bf      = %w{ bf_skey bf_ecb bf_enc bf_cfb64 bf_ofb64 }

      f_cast    = %w{ c_skey c_ecb c_enc c_cfb64 c_ofb64 }

      f_camellia = %w{ cmll_ecb     cmll_ofb  cmll_cfb  cmll_ctr  cmll_utl
                       cmll-x86_64  cmll_misc }

      f_seed    = %w{ seed seed_ecb seed_cbc seed_cfb seed_ofb }

      f_modes   = %w{ cbc128   ctr128   cts128   cfb128   ofb128   gcm128
                      ccm128   xts128   ghash-x86_64 }

      f_bn      = %w{ bn_add      bn_blind     bn_const     bn_ctx
                      bn_depr     bn_div       bn_err       bn_exp
                      bn_exp2     bn_gcd       bn_gf2m      bn_kron
                      bn_lib      bn_mod       bn_mont      bn_mpi
                      bn_mul      bn_nist      bn_prime     bn_print
                      bn_rand     bn_recp      bn_shift     bn_sqr
                      bn_sqrt     bn_word      bn_x931p     modexp512-x86_64
                      x86_64-gcc  x86_64-gf2m  x86_64-mont  x86_64-mont5 }

      f_ec      = %w{ ec2_mult      ec2_smpl      ec_ameth      ec_asn1
                      ec_check      ec_curve      ec_cvt        ec_err
                      ec_key        ec_lib        ec_mult       ec_pmeth
                      ec_print      eck_prn       ecp_mont      ecp_nist
                      ecp_nistp224  ecp_nistp256  ecp_nistp521  ecp_nistputil
                      ecp_oct       ec2_oct       ec_oct        ecp_smpl }

      f_rsa     = %w{ rsa_eay    rsa_gen   rsa_lib    rsa_sign
                      rsa_saos   rsa_err   rsa_pk1    rsa_ssl
                      rsa_none   rsa_oaep  rsa_chk    rsa_null
                      rsa_pss    rsa_x931  rsa_asn1   rsa_depr
                      rsa_ameth  rsa_prn   rsa_pmeth  rsa_crpt }

      f_dsa     = %w{ dsa_gen   dsa_key    dsa_lib    dsa_asn1
                      dsa_vrf   dsa_sign   dsa_err    dsa_ossl
                      dsa_depr  dsa_ameth  dsa_pmeth  dsa_prn }

      f_ecdsa   = %w{ ecs_lib  ecs_asn1  ecs_ossl  ecs_sign  ecs_vrf  ecs_err }

      f_dh      = %w{ dh_asn1  dh_gen   dh_key    dh_lib    dh_check
                      dh_err   dh_depr  dh_ameth  dh_pmeth  dh_prn }

      f_ecdh    = %w{ ech_lib ech_ossl ech_key ech_err }

      f_dso     = %w{ dso_dl    dso_dlfcn    dso_err    dso_lib
                      dso_null  dso_openssl  dso_win32  dso_vms
                      dso_beos }

      f_engine  = %w{ eng_err      eng_lib    eng_list   eng_init
                      eng_ctrl     eng_table  eng_pkey   eng_fat
                      eng_all      tb_rsa     tb_dsa     tb_ecdsa
                      tb_dh        tb_ecdh    tb_rand    tb_store
                      tb_cipher    tb_digest  tb_pkmeth  tb_asnmth
                      eng_openssl  eng_cnf    eng_dyn    eng_cryptodev
                      eng_rsax     eng_rdrand }

      f_buffer  = %w{ buffer  buf_str  buf_err }

      f_bio     = %w{ bio_lib  bio_cb    bio_err   bss_mem   bss_null
                      bss_fd   bss_file  bss_sock  bss_conn  bf_null
                      bf_buff  b_print   b_dump    b_sock    bss_acpt
                      bf_nbio  bss_log   bss_bio   bss_dgram }

      f_stack   = %w{ stack }

      f_lhash   = %w{ lhash lh_stats }

      f_rand    = %w{ md_rand   randfile  rand_lib   rand_err
                      rand_egd  rand_win  rand_unix  rand_os2  rand_nw }

      f_err     = %w{ err err_all err_prn }

      f_evp     = %w{ encode    digest    evp_enc    evp_key   evp_acnf
                      e_des     e_bf      e_idea     e_des3    e_camellia
                      e_rc4     e_aes     names      e_seed    e_xcbc_d
                      e_rc2     e_cast    e_rc5      m_null    m_md2
                      m_md4     m_md5     m_sha      m_sha1    m_wp
                      m_dss     m_dss1    m_mdc2     m_ripemd  m_ecdsa
                      p_open    p_seal    p_sign     p_verify  p_lib
                      p_enc     p_dec     bio_md     bio_b64   bio_enc
                      evp_err   e_null    c_all      c_allc    c_alld
                      evp_lib   bio_ok    evp_pkey   evp_pbe   p5_crpt
                      p5_crpt2  e_old     pmeth_lib  pmeth_fn  pmeth_gn
                      m_sigver  evp_fips  e_aes_cbc_hmac_sha1  e_rc4_hmac_md5 }

      f_asn1    = %w{ a_object  a_bitstr a_utctm     a_gentm
                      a_time    a_int     a_octet    a_print
                      a_type    a_set     a_dup      a_d2i_fp
                      a_i2d_fp  a_enum    a_utf8     a_sign
                      a_digest  a_verify  a_mbstr    a_strex
                      x_algor   x_val     x_pubkey   x_sig
                      x_req     x_attrib  x_bignum   x_long
                      x_name    x_x509    x_x509a    x_crl
                      x_info    x_spki    nsseq      x_nx509
                      d2i_pu    d2i_pr    i2d_pu     i2d_pr
                      t_req     t_x509    t_x509a    t_crl
                      t_pkey    t_spki    t_bitst    tasn_new
                      tasn_fre  tasn_enc  tasn_dec   tasn_utl
                      tasn_typ  tasn_prn  ameth_lib  f_int
                      f_string  n_pkey    f_enum     x_pkey
                      a_bool    x_exten   bio_asn1   bio_ndef
                      asn_mime  asn1_gen  asn1_par   asn1_lib
                      asn1_err  a_bytes   a_strnid   evp_asn1
                      asn_pack  p5_pbe    p5_pbev2   p8_pkey
                      asn_moid }

      f_pem     = %w{ pem_sign  pem_seal  pem_info  pem_lib  pem_all
                      pem_err   pem_x509  pem_xaux  pem_oth  pem_pk8
                      pem_pkey  pvkfmt }

      f_x509    = %w{ x509_def  x509_d2   x509_r2x  x509_cmp  x509_obj
                      x509_req  x509spki  x509_vfy  x509_set  x509cset
                      x509rset  x509_err  x509name  x509_v3   x509_ext
                      x509_att  x509type  x509_lu   x_all     x509_txt
                      x509_trs  by_file   by_dir    x509_vpm }

      f_x509v3  = %w{ v3_bcons   v3_bitst  v3_conf   v3_extku
                      v3_ia5     v3_lib    v3_prn    v3_utl
                      v3err      v3_genn   v3_alt    v3_skey
                      v3_akey    v3_pku    v3_int    v3_enum
                      v3_sxnet   v3_cpols  v3_crld   v3_purp
                      v3_info    v3_ocsp   v3_akeya  v3_pmaps
                      v3_pcons   v3_ncons  v3_pcia   v3_pci
                      pcy_cache  pcy_node  pcy_data  pcy_map
                      pcy_tree   pcy_lib   v3_asid   v3_addr }

      f_conf    = %w{ conf_err  conf_lib   conf_api  conf_def
                      conf_mod  conf_mall  conf_sap }

      f_txt_db  = %w{ txt_db }

      f_pkcs7   = %w{ pk7_asn1   pk7_lib   pkcs7err  pk7_doit
                      pk7_smime  pk7_attr  pk7_mime  bio_pk7 }

      f_pkcs12  = %w{ p12_add   p12_asn   p12_attr  p12_crpt
                      p12_crt   p12_decr  p12_init  p12_key
                      p12_kiss  p12_mutl  p12_utl   p12_npas
                      pk12err   p12_p8d   p12_p8e }

      f_comp    = %w{ comp_lib  comp_err  c_rle  c_zlib }

      f_ocsp    = %w{ ocsp_asn  ocsp_ext  ocsp_ht   ocsp_lib  ocsp_cl
                      ocsp_srv  ocsp_prn  ocsp_vfy  ocsp_err }

      f_ui      = %w{ ui_err  ui_lib  ui_openssl  ui_util  ui_compat }

      f_krb5    = %w{ krb5_asn }

      f_cms     = %w{ cms_lib    cms_asn1  cms_att  cms_io
                      cms_smime  cms_err   cms_sd   cms_dd
                      cms_cd     cms_env   cms_enc  cms_ess  cms_pwri }

      f_pqueue  = %w{ pqueue }

      f_ts      = %w{ ts_err          ts_req_utils  ts_req_print   ts_rsp_utils
                      ts_rsp_print    ts_rsp_sign   ts_rsp_verify  ts_verify_ctx
                      ts_lib ts_conf  ts_asn1 }

      f_srp     = %w{ srp_lib srp_vfy }

      f_cmac    = %w{ cmac  cm_ameth  cm_pmeth }

      # files in 'engines' linked in to libcrypt.a for static build but each is an
      # independent shared library for dynamic build
      #
      f_eng = %w{ e_4758cca  e_aep       e_atalla  e_cswift   e_gmp  e_chil
                  e_nuron    e_sureware  e_ubsec   e_padlock  e_capi }

      # files in engines/ccgost linked in to libcrypt.a for static build but are linked
      # into libgost.so for dynamic build
      #
      @f_ccgost = %w{ e_gost_err   gost2001_keyx  gost2001    gost89
                      gost94_keyx  gost_ameth     gost_asn1   gost_crypt
                      gost_ctl     gost_eng       gosthash    gost_keywrap
                      gost_md      gost_params    gost_pmeth  gost_sign }

      f_engines = if :static == @build.link_type
                    @f_ccgost + f_eng
                  else
                    f_eng
                  end

      # concatenate all lists together, checking for duplicates
      all = [f_objects,   f_md4,     f_md5,       f_sha,   f_mdc2,
             f_hmac,      f_ripemd,  f_whrlpool,  f_des,   f_aes,
             f_rc2,       f_rc4,     f_idea,      f_bf,    f_cast,
             f_camellia,  f_seed,    f_modes,     f_bn,    f_ec,
             f_rsa,       f_dsa,     f_ecdsa,     f_dh,    f_ecdh,
             f_dso,       f_engine,  f_buffer,    f_bio,   f_stack,
             f_lhash,     f_rand,    f_err,       f_evp,   f_asn1,
             f_pem,       f_x509,    f_x509v3,    f_conf,  f_txt_db,
             f_pkcs7,     f_pkcs12,  f_comp,      f_ocsp,  f_ui,
             f_krb5,      f_cms,     f_pqueue,    f_ts,    f_srp,
             f_cmac,      f_engines]
      @f_crypto = all.inject( f_base ){ |m, v| m += v }

      # check for duplicates
      cnt = @f_crypto.size
      @f_crypto.uniq!
      cnt -= @f_crypto.size
      raise "Duplicates in @f_crypto: %d" % cnt if cnt > 0

    end  # set_include

    def initialize build    # see notes at Bundle.initialize
      super
      @dir_root = '.'    # not 'crypto' since we need files from sibling directory

      set_exclude
      set_include

      # libraries -- array of hashes, one per library; each library needs these keys:
      #
      #  :name   -- name of dynamic library excluding extension
      #  :files  -- set of object files, excluding extension
      #  :libs   -- set of user library dependencies [optional]
      #  :linker -- :ld_cc or :ld_cxx for C or C++ linking respectively
      #

      if :static == @build.link_type
        @libraries = [{ :name => 'libcrypto',
                        :files => @f_crypto,
                        :linker => :ld_cc }]

        # default targets to build
        @targets = ['libcrypto', :lib]
      else
        # NOTE: There is a circular dependency: libcrypto uses ENGINE_load_atalla,
        # ENGINE_load_aep from libatalla, libaep, etc. (eng_all.c) but those use
        # ENGINE_set_name etc. from libcrypto
        #
        @libraries = [{
                        :name   => 'libcrypto',
                        :files  => @f_crypto,
                        # :libs   => %w{ libgost    libchil  lib4758cca
                        #                libnuron   libaep   libsureware
                        #                libatalla  libubsec libcswift
                        #                libpadlock libgmp   libcapi },
                        :linker => :ld_cc
                      }, {
                        :name   => 'libgost',
                        :files  => @f_ccgost,
                        :libs   => ['libcrypto'],
                        :linker => :ld_cc 
                      }, {
                        :name   => 'libchil',
                        :files  => ['e_chil'],
                        :libs   => ['libcrypto'],
                        :linker => :ld_cc 
                      }, {
                        :name   => 'lib4758cca',
                        :files  => ['e_4758cca'],
                        :libs   => ['libcrypto'],
                        :linker => :ld_cc 
                      }, {
                        :name   => 'libnuron',
                        :files  => ['e_nuron'],
                        :libs   => ['libcrypto'],
                        :linker => :ld_cc 
                      }, {
                        :name   => 'libaep',
                        :files  => ['e_aep'],
                        :libs   => ['libcrypto'],
                        :linker => :ld_cc 
                      }, {
                        :name   => 'libsureware',
                        :files  => ['e_sureware'],
                        :libs   => ['libcrypto'],
                        :linker => :ld_cc 
                      }, {
                        :name   => 'libatalla',
                        :files  => ['e_atalla'],
                        :libs   => ['libcrypto'],
                        :linker => :ld_cc 
                      }, {
                        :name   => 'libubsec',
                        :files  => ['e_ubsec'],
                        :libs   => ['libcrypto'],
                        :linker => :ld_cc 
                      }, {
                        :name   => 'libcswift',
                        :files  => ['e_cswift'],
                        :libs   => ['libcrypto'],
                        :linker => :ld_cc 
                      }, {
                        :name   => 'libpadlock',
                        :files  => ['e_padlock'],
                        :libs   => ['libcrypto'],
                        :linker => :ld_cc 
                      }, {
                        :name   => 'libgmp',
                        :files  => ['e_gmp'],
                        :libs   => ['libcrypto'],
                        :linker => :ld_cc 
                      }, {
                        :name   => 'libcapi',
                        :files  => ['e_capi'],
                        :libs   => ['libcrypto'],
                        :linker => :ld_cc 
                      }]
        # default targets to build
        @targets = ['libcrypto',  :lib, 'libgost',    :lib]

        # @targets += ['libchil',    :lib, 'lib4758cca',  :lib,
        #              'libnuron',   :lib, 'libaep',   :lib, 'libsureware', :lib,
        #              'libatalla',  :lib, 'libubsec', :lib, 'libcswift',   :lib,
        #              'libpadlock', :lib, 'libgmp',   :lib, 'libcapi',     :lib]
                    
      end  # :static check
    end  # initialize

    def create_dirs    # create subdirectories under obj_root

      # Step 1: Create directories under crypto
      dir = File.join @build.obj_root, 'crypto'

      # these need the 'asm' subdirectory
      alist = %w{ aes modes des bf rc5 sha rc4 cast camellia ripemd md5 whrlpool bn }

      list = %w{ objects md4     md5     sha     mdc2   hmac    ripemd  whrlpool
                 des     aes     rc2     rc4     idea   bf      cast    camellia
                 seed    modes   bn      ec      rsa    dsa     ecdsa   dh
                 ecdh    dso     engine  buffer  bio    stack   lhash   rand
                 err     evp     asn1    pem     x509   x509v3  conf    txt_db
                 pkcs7   pkcs12  comp    ocsp    ui     krb5    cms     pqueue
                 ts      srp     cmac }

      dynamic = :dynamic == @build.link_type
      dlist = []    # list of directories to create
      dlist << File.join( dir, 'static' ) if !dynamic
      list.each{ |d|
        base = File.join dir, d
        path = dynamic ? base : File.join( base, 'static' )
        dlist << path
        if alist.include? d    # needs asm subdirectory
          asm = File.join base, 'asm'
          path = dynamic ? asm : File.join( asm, 'static' )
          dlist << path
        end
      }
      cmd = 'mkdir -p ' + dlist * ' '    # one long command
      Util.run_cmd cmd, Build.logger

      # Step 2: Create sibling directories
      dlist = []
      list = [ 'engines', File.join( 'engines', 'ccgost' ), 'ssl', 'apps' ]
      list.each{ |d|
        path = File.join @build.obj_root, d
        path = File.join( path, 'static' ) if !dynamic
        dlist << path
      }
      cmd = 'mkdir -p ' + dlist * ' '
      Util.run_cmd cmd, Build.logger

    end  # create_dirs

    def add_gen_asm    # add generated assembler files
      log = Build.logger
      log.debug "Adding generated assembler files ..."

      # NOTE: This code is x86_64 specific and will need changes for other architectures

      # pairs: directory, list of pairs of: [perl script, output file]
      dirs = [ '.',        [['x86_64cpuid.pl',            'x86_64cpuid.s']],
               'aes',      [['asm/vpaes-x86_64.pl',       'vpaes-x86_64.s'],
                            ['asm/bsaes-x86_64.pl',       'bsaes-x86_64.s'],
                            ['asm/aesni-x86_64.pl',       'aesni-x86_64.s'],
                            ['asm/aesni-sha1-x86_64.pl',  'aesni-sha1-x86_64.s'],
                            ['asm/aes-x86_64.pl',         'aes-x86_64.s']],

               'modes',    [['asm/ghash-x86_64.pl',       'ghash-x86_64.s']],

               'sha',      [['asm/sha1-x86_64.pl',        'sha1-x86_64.s'],
                            ['asm/sha512-x86_64.pl',      'sha256-x86_64.s'],
                            ['asm/sha512-x86_64.pl',      'sha512-x86_64.s']],

               'rc4',      [['asm/rc4-x86_64.pl',         'rc4-x86_64.s'],
                            ['asm/rc4-md5-x86_64.pl',     'rc4-md5-x86_64.s']],

               'camellia', [['asm/cmll-x86_64.pl',        'cmll-x86_64.s']],

               'md5',      [['asm/md5-x86_64.pl',         'md5-x86_64.s']],

               'whrlpool', [['asm/wp-x86_64.pl',          'wp-x86_64.s']],

               'bn',       [['asm/modexp512-x86_64.pl',   'modexp512-x86_64.s'],
                            ['asm/x86_64-mont.pl',        'x86_64-mont.s'],
                            ['asm/x86_64-mont5.pl',       'x86_64-mont5.s'],
                            ['asm/x86_64-gf2m.pl',        'x86_64-gf2m.s']] ]

      base = File.join @build.src_root, 'crypto'
      dirs.each_slice( 2 ){ |dir, pairs|     # dir is subdirectory of dir_root
        #puts "dir = %s, pairs.size = %d" % [dir, pairs.size]
        pairs.each{ |(sf, of)|    # script file, output file
          #puts "sf = %s, of = %s" % [sf, of]
          if '.' == dir
            s_path = File.join base, sf
            o_path = File.join @build.obj_root, 'crypto', of
          else
            s_path = File.join base, dir, sf
            o_path = File.join @build.obj_root, 'crypto', dir, of
          end
          raise "Script #{s_path} not found" if ! File.exist? s_path

          if !File.exist?( o_path ) ||
              File.stat( o_path ).mtime < File.stat( s_path ).mtime

            # assembler file does not exist or predates script file; regenerate it
            os = Build.system.darwin? ? 'macosx' : 'elf'
            cmd = 'perl %s %s %s' % [s_path, os, o_path]
            log.debug "Command: #{cmd}"
            `#{cmd}`
            raise "Command '#{cmd}' failed" if ! $?.to_i.zero?
          end

          # add source and object targets (the 'false' argument to add_object
          # suppresses replacement of src_root with obj_root in the file path that is
          # normally done for source files found under src_root).
          #
          @build.add_object o_path, nil, false
        }
      }
      log.debug "... done adding generated assembler file."
    end  # add_gen_asm

    def adjust_options
      crypto = File.join @build.src_root, 'crypto'
      asn1 = File.join crypto, 'asn1'
      evp  = File.join crypto, 'evp'
      modes = File.join crypto, 'modes'

      # these files include asn1_locl.h
      tlist = %w{ hm_ameth  ec_ameth  rsa_ameth  dsa_ameth  dh_ameth  tb_asnmth
                  p_lib     evp_pkey  pmeth_lib  pem_lib    pem_pkey  pk7_lib
                  cms_sd    cms_env   cms_pwri   cm_ameth }
      opt = [ "-I#{asn1}" ]
      @build.add_target_options( :targets     => tlist,
                                 :target_type => :obj,
                                 :options     => opt,
                                 :option_type => :cpp )

      # these files include evp_locl.h
      tlist = %w{ hm_pmeth  ec_pmeth  rsa_pmeth  dsa_pmeth dh_pmeth  cm_pmeth }
      opt = [ "-I#{evp}" ]
      @build.add_target_options( :targets     => tlist,
                                 :target_type => :obj,
                                 :options     => opt,
                                 :option_type => :cpp )

      # these files include modes_lcl.h
      opt = [ "-I#{modes}" ]
      @build.add_target_options( :targets     => ['e_aes'],
                                 :target_type => :obj,
                                 :options     => opt,
                                 :option_type => :cpp )

      if :dynamic == @build.link_type
        tlist = %w{ libgost lib4758cca libchil libnuron libaep libsureware
                    libatalla libubsec libcswift libpadlock libgmp libcapi }
        opt = [ "-lcrypto" ]
        @build.add_target_options( :targets     => tlist,
                                   :target_type => :lib,
                                   :options     => opt )
      end
    end  # adjust_options

    def setup    # main entry point to configure libcrypto
      log = Build.logger
      log.debug "Setting up LibCrypto ..."

      # create necessary directories
      create_dirs

      # add generated assembler files
      add_gen_asm

      # discover source files and create associated targets
      discover_targets

      # add library targets
      add_lib_targets

      # add executable targets
      add_exe_targets

      # adjust options for some targets
      adjust_options

      # default targets to build (may be modified by customize() and later, possibly,
      # by commandline options
      #
      add_default_targets

      log.debug "... done setting up LibCrypto"
    end  # setup

    Build.add_bundle self
  end  # LibCrypto

  class LibSSL < Bundle    # libssl needs libcrypto

    # helper routine to add to exclude list
    # list of files, subdirectory, parent directory
    #
    def add_ex list, d, p = 'ssl'
      list.map!{ |f| File.join p, d, f }
      # common = @exclude & list
      # raise "Duplicates: #{common}" if ! common.empty?
      @exclude += list
    end  # add_ex

    def initialize build    # see notes at Bundle.initialize
      super
      @dir_root = 'ssl'

      # exclude files for 'ssl' directory
      @exclude = %w{ ssltest.c ssl_task.c }.map{ |f| File.join 'ssl', f }

      # set of files in libssl
      f_ssl = Set.new %w{ s2_meth   s2_srvr   s2_clnt   s2_lib    s2_enc    s2_pkt
                          s3_meth   s3_srvr   s3_clnt   s3_lib    s3_enc    s3_pkt
                          s3_both   s23_meth  s23_srvr  s23_clnt  s23_lib   s23_pkt
                          t1_meth   t1_srvr   t1_clnt   t1_lib    t1_enc    d1_meth
                          d1_srvr   d1_clnt   d1_lib    d1_pkt    d1_both   d1_enc
                          d1_srtp   ssl_lib   ssl_err2  ssl_cert  ssl_sess  ssl_ciph
                          ssl_stat  ssl_rsa   ssl_asn1  ssl_txt   ssl_algs  bio_ssl
                          ssl_err   kssl      tls_srp   t1_reneg }

      # libraries -- array of hashes, one per library; each library needs these keys:
      #
      #  :name   -- name of dynamic library excluding extension
      #  :files  -- set of object files, excluding extension
      #  :libs   -- set of user library dependencies [optional]
      #  :linker -- :ld_cc or :ld_cxx for C or C++ linking respectively
      #
      @libraries = [{ :name   => 'libssl',
                      :files  => f_ssl,
                      :libs   => ['libcrypto'],
                      :linker => :ld_cc }]

      # default targets to build
      @targets = ['libssl', :lib]
    end  # initialize

    def create_dirs    # create subdirectories under obj_root
      path = File.join @build.obj_root, 'ssl'
      path = File.join( path, 'static' ) if  :static == @build.link_type
      cmd = "mkdir -p #{path}"
      Util.run_cmd cmd, Build.logger
    end  # create_dirs

    def setup    # main entry point to configure libcrypto
      log = Build.logger
      log.debug "Setting up LibSSL ..."

      # create necessary directories
      create_dirs

      # discover source files and create associated targets
      discover_targets

      # add library targets
      add_lib_targets

      # add executable targets
      add_exe_targets

      # default targets to build (may be modified by customize() and later, possibly,
      # by commandline options
      #
      add_default_targets

      log.debug "... done setting up LibSSL"
    end  # setup

    Build.add_bundle self
  end  # LibSSL

  class Apps < Bundle

    # helper routine to add to exclude list
    # list of files, subdirectory, parent directory
    #
    def add_ex list, d, p = 'apps'
      list.map!{ |f| File.join p, d, f }
      # common = @exclude & list
      # raise "Duplicates: #{common}" if ! common.empty?
      @exclude += list
    end  # add_ex

    def initialize build    # see notes at Bundle.initialize
      super
      @dir_root = 'apps'

      @exclude = %w{ vms_decc_init.c md4.c winrand.c }.map{ |f| File.join @dir_root, f }
      @exclude += %w{ demoCA demoSRP set }

      # list of files in openssl; we need this later in adjust_options
      @f_openssl = %w{ openssl  verify  asn1pars  req       dgst      dh         dhparam
                       enc      passwd  gendh     errstr    ca        pkcs7      crl2p7
                       crl      rsa     rsautl    dsa       dsaparam  ec         ecparam
                       x509     genrsa  gendsa    genpkey   s_server  s_client   speed
                       s_time   apps    s_cb      s_socket  app_rand  version    sess_id
                       ciphers  nseq    pkcs12    pkcs8     pkey      pkeyparam  pkeyutl
                       spkac    smime   cms       rand      engine    ocsp       prime
                       ts       srp }

      # an executable is defined by a name, list of objects and libraries and type of link
      args = { :name => 'openssl', :files => @f_openssl, :linker => :ld_cc }
      args[ :libs ] = ['libssl']
      @executables = [ args ]

      # default targets to build
      @targets = ['openssl', :exe]
    end  # initialize

    def create_dirs    # create subdirectories under obj_root
      path = File.join @build.obj_root, @dir_root
      path = File.join( path, 'static' ) if :static == @build.link_type
      cmd = "mkdir -p #{path}"
      Util.run_cmd cmd, Build.logger
    end  # create_dirs

    def adjust_options
      opt = [ "-DMONOLITH" ]
      @build.add_target_options( :targets     => @f_openssl,
                                 :target_type => :obj,
                                 :options     => opt,
                                 :option_type => :cpp )

      @build.add_target_options( :targets     => ['openssl'],
                                 :target_type => :exe,
                                 :options     => ['-ldl'] )
    end  # adjust_options

    def setup    # main entry point to configure libcrypto
      log = Build.logger
      log.debug "Setting up Apps ..."

      # create necessary directories
      create_dirs

      # discover source files and create associated targets
      discover_targets

      # add library targets
      add_lib_targets

      # add executable targets
      add_exe_targets

      # adjust options for some targets
      adjust_options

      # default targets to build (may be modified by customize() and later, possibly,
      # by commandline options
      #
      add_default_targets

      log.debug "... done setting up Apps"
    end  # setup

    Build.add_bundle self
  end  # Apps

end  # Build

Build.start
