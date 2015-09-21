CTFPad
======

A web UI and server for task based competitions employing Etherpad Lite. It features CTF and Task managemeent, CTF&Task based file uploads and user assignment. May be used for other purposes.

Installing
-----

- acquire Node.JS v10.x and npm, sqlite3 and openssl
- check if `node` is in PATH, create a link to `nodejs` if necessary (usually necessary on Debian/Ubuntu)
- execute`npm install`
- install etherpad-lite into `etherpad-lite` (see `https://github.com/ether/etherpad-lite`) and run it once to install all the dependencies
- create ctfpad.sqlite with ctfpad.sql (on Debian use `sqlite3 ctfpad.sqlite < ctfpad.sql`)
- if necessary, create a keypair with `new_certs.sh` (or use any other certificate pair)
- copy `config.json.example` to `config.json` and tweak to your needs (see **Configuration**)
- create a directory named `uploads` or soft link another location

Configuration
-----

### CTFPad
- port: TCP port the CTFPad will listen on
- etherpad\_port: TCP port where Etherpad Lite will be reachable from the outside
- etherpad\_internal\_port: TCP port where Etherpad Lite is reachable locally
- keyfile: location of the SSL key file
- certfile: location of the SSL cert file
- authkey: a *secret* string needed to register

### Etherpad Lite
Follow the instructions on the project pages. **It is recommended to configure Etherpad Lite to only listen locally.** The CTFPad will provide an authenticating proxy for accessing Etherpad Lite.

Running
-----
Start the server by running `node main.js` or `coffee main.coffee` if Coffeescript ist installed globally.

Using
-----
If you are using a self-signed certificate (which is the case for certificates generated with `new_certs.sh`) it may be necessary to access `https://$host:$etherpad_port` directly to add an certificate exception since most browsers do not allow adding exceptions for iframes.

