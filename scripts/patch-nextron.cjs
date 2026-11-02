const fs = require('fs')
const path = require('path')

const file = path.join(__dirname, '..', 'node_modules', 'nextron', 'bin', 'nextron.cjs')
if (!fs.existsSync(file)) {
  process.exit(0)
}

let s = fs.readFileSync(file, 'utf8')

// Helper to stop the Electron child
const killHelperDef = `K=(p)=>{if(!p)return;try{p.kill('SIGTERM')}catch(e){}},`

// 1. Add K helper to declarations
if (!s.includes('K=(p)=>')) {
  s = s.replace('a=!0,o,s,c,l,', 'a=!0,o,s,c,l,' + killHelperDef)
}

// 2. Patch f() to ensure K(c) is called before starting new one
if (!s.includes('f=()=>{K(c);')) {
  s = s.replace('f=()=>{', 'f=()=>{K(c);')
}

// 3. Patch m() cleanup to kill tree of c and l
if (s.includes('c&&c.kill(),l&&l.kill()')) {
  s = s.replace('c&&c.kill(),l&&l.kill()', 'K(c),K(l)')
}

// 4. Patch watch callback to use K(c) instead of c.kill()
if (s.includes('!a&&c&&c.kill()')) {
  s = s.replace('!a&&c&&c.kill()', '!a&&K(c)')
}

// 5. Patch default startupDelay from 0 to 20000ms (Nextron bug: defaults to 0ms instead of 10000ms, causing an immediate timeout before Next.js compiles)
if (s.includes('r.startupDelay||e.startupDelay||0')) {
  s = s.replace('r.startupDelay||e.startupDelay||0', 'r.startupDelay||e.startupDelay||20000')
}

// 6. Spawn Electron attached. Inheriting our stdio keeps the app's console
//    output in the dev terminal. `c.unref()` on the next line only makes sense
//    for a detached child, so it is dropped along with the flag.
if (s.includes('{detached:!0,reject:!1}),c.catch(()=>{}),c.unref()')) {
  s = s.replace(
    '{detached:!0,reject:!1}),c.catch(()=>{}),c.unref()',
    '{detached:!1,reject:!1,stdio:`inherit`}),c.catch(()=>{})'
  )
}

// 7. Optional: rebuild main/ without relaunching Electron, for when the restart
//    churn gets in the way. Set NEXTRON_NO_RESTART=1 to enable.
//    `a` is nextron's first-run flag: on the first watcher callback it skips the
//    kill, runs f() to do the initial launch, then clears itself. Only the
//    restarts after that are suppressed here, so the app still starts normally.
if (!s.includes('NEXTRON_NO_RESTART')) {
  s = s.replace(
    'e.runOnly||(!a&&K(c),f(),a&&=!1)',
    'e.runOnly||(a?(f(),a&&=!1):process.env.NEXTRON_NO_RESTART?console.log(`[deskNotch] main rebuilt — restart skipped (NEXTRON_NO_RESTART=1)`):(K(c),f()))'
  )
}

fs.writeFileSync(file, s, 'utf8')
console.log('[deskNotch] Successfully patched nextron.cjs with process tree killer')
