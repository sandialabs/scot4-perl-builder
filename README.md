# scot4-perl-builder

Builds the custom perl binary and related container image for flair and scot4-inbox

# manual interventions

There are several modules that may break as authors abandon their releases.

- Test::mysqld = filed a bug report https://github.com/kazuho/p5-test-mysqld/issues/38
    - cpanm --force and hope for the best
        - had to cpanm --look
        - delete t/05-*
        - perl Build.PL
        - ./Build && ./Build test && ./Build install

- Crypt::Curve25519 - compilation fails - author unresponsive 
    - https://github.com/ajgb/crypt-curve25519/issues/9
    - Solution:
        - sudo -E cpanm --look Crypt::Curve25519
        - grep -rl fmul | xargs sed -i 's/fmul/fixedvar/g'
        - perl Makefile.PL
        - make
        - make test
        - make install
        - exit
