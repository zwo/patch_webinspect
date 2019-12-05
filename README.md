# Enable debugging any App's WebView on MacOS

This is a PoC to enable debugging WebView in any App, by patching `WebInspect` the dylib regulating which App can be debugged by Safari.

The idea is to tweak method `-[RWIRelayDelegateMac _allowApplication:bundleIdentifier:]`to always return TRUE.

As notice from the disassembled flow diagram, function `isProxyApplication` is one of the judgement conditions. Moreover, from the opcodes, we see `bl` is set before test, so we can change `test al, al` to `test bl, bl`.

![Flow diagram](Image/01.png)

Just get it done by patching opcode `84 CO` to `84 DB`. However, the location of this opcode may vary in different OS versions. In this example is 0x6daaf. 

![opcode](Image/02.png)

### How to use

First of all, disable SIP (System Integrity Protection), otherwise, `task_for_pid` won't work. 

**Warning!** disabling SIP is at your own risk, you should make sure your environment is safe by yourself.

```bash

```



Then you should analyze by path above with IDA, Hopper, etc.

```objc
xxx
```

