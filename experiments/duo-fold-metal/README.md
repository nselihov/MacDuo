# iPhone Duo fold port: isolated Metal study

This study renders one generated test image through a single Metal shader at
115°, 80°, 60° and 40°. It does not change the MacDuo application, capture the
desktop, or replace the lock-screen renderer. Run `./run.sh`; output goes to
`.build/reference-port/metal-prototype/`.

The shader adapts the fold projection, mipmapped bicubic blur, and edge shading
from [iPhone Duo Animation](https://github.com/akashtdev/iphone-duo-animation/)
by Akash T. The source is MIT licensed; see `LICENSE-reference.txt`. The phone's
vertical hinge is rotated to a MacBook's horizontal hinge. The scene is generated
locally so texture movement can be judged without application content.
