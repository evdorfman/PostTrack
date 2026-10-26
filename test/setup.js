// The app's source file expects `React` as a bare global (the production
// build loads React from a <script> tag, as window.React, and the JSX
// factory it compiles to — React.createElement/React.memo/etc. — is just
// source text referencing that global, not an import binding). A handful
// of components call React.memo(...) at module scope, so even importing
// the built test module (not rendering anything) needs this set first.
import * as React from "react";
globalThis.React = React;
