# Grand Convergence Bug Fixes Documentation

This document records all bug fixes applied to the grand-conv v1.0 codebase.
These fixes should be ported to the v2.0 (dev) codebase as well.

---

## C Source Fixes

### 1. GCC 10+ Multiple-Definition Linker Errors

**File:** `src/paml.h` (lines 372-374)
**Symptom:** Linker fails with "multiple definition" errors when compiled with GCC 10+ (which defaults to `-fno-common`).
**Root cause:** Enum declarations included variable names, causing each translation unit to define a global variable.
**Fix:** Remove variable names from enum declarations.

```c
// Before:
enum {BASEseq=0, CODONseq, AAseq, CODON2AAseq, BINARYseq, BASE5seq} SeqTypes;
enum {PrBranch=1, PrNodeNum=2, PrLabel=4, PrAge=8, PrOmega=16} OutTreeOptions;

// After:
enum {BASEseq=0, CODONseq, AAseq, CODON2AAseq, BINARYseq, BASE5seq};
enum {PrBranch=1, PrNodeNum=2, PrLabel=4, PrAge=8, PrOmega=16};
```

**Note for v2.0:** The dev version still names these enums (for icc compatibility). The fix approach may differ — either remove names or use `extern` properly.

---

### 2. Stack Buffer Overflow in getSelectedBranches()

**File:** `src/codeml.c`, `getSelectedBranches()` function (around line 1567)
**Symptom:** Segfault during sequence translation when branch pairs are specified in the control file.
**Root cause:** VLA `char values[end-start]` is one byte too small for the null terminator. `strncpy` does not null-terminate when the source is exactly `end-start` bytes.
**Fix:** Allocate +1 for null terminator and explicitly null-terminate.

```c
// Before:
char values[end-start];
strncpy(values, line+start, end-start);

// After:
char values[end-start+1];
strncpy(values, line+start, end-start);
values[end-start] = '\0';
```

---

### 3. Integer Overflow in calculateRegression()

**File:** `src/JDKLabUtility.c`, `calculateRegression()` function (around line 153)
**Symptom:** Segfault or massive memory allocation failure on trees with many branch pairs (e.g., 227 species = 51,400 branch pairs). `numBranchPairs * numBranchPairs * sizeof(double)` overflows a 32-bit int.
**Root cause:** The original code allocated an O(n^2) matrix of all pairwise slopes, which for large trees requires tens of GB and overflows int multiplication.
**Fix:** Rewrite to a two-pass approach: pass 1 counts non-zero slopes, pass 2 collects them directly into a vector. This is O(n^2) in time but O(counter) in memory, where counter is typically much smaller than n^2.

```c
// Before:
double *vector = (double*)malloc(numBranchPairs*numBranchPairs*sizeof(double));
// single pass filling vector[counter++]

// After:
// Pass 1: count non-zero slopes
int counter = 0;
for(i...) for(j...) { if(slope != 0) counter++; }

// Pass 2: collect into right-sized vector
double *vector = (double*)malloc((size_t)counter * sizeof(double));
for(i...) for(j...) { if(slope != 0) vector[index++] = slope; }
```

**Note for v2.0:** The dev version still uses the O(n^2) allocation and will crash on large trees. Both `calculateRegression()` and `calculateRegressionRestricted()` need this fix.

---

### 4. Off-by-One Heap Overflow in makeupDataOutput()

**File:** `src/JDKLabUtility.c`, `makeupDataOutput()` function (around line 64)
**Symptom:** Heap buffer overflow detected by AddressSanitizer.
**Root cause:** `realloc(data, strlen(data) + strlen(name) + 3)` allocates space for " = " (3 chars) but forgets the null terminator (+1).
**Fix:** Change `+3` to `+4`.

```c
// Before:
data = realloc(data, strlen(data) + strlen(name) + 3);

// After:
data = realloc(data, strlen(data) + strlen(name) + 4);
```

---

### 5. Zero-Size Malloc Overflow in outputDataInJS()

**File:** `src/JDKLabUtility.c`, `outputDataInJS()` function (around line 348)
**Symptom:** Heap buffer overflow when `numOfSelectedBranchPairs == 0`.
**Root cause:** `malloc(20 * numOfSelectedBranchPairs)` returns a zero-size (or very small) allocation, then `strcpy` writes "[ " into it.
**Fix:** Add `+4` minimum to all three allocations for the "[ ]" content.

```c
// Before:
char *siteSpecificBranchPairs = (char*)malloc(20*numOfSelectedBranchPairs*sizeof(char));
char *siteSpecificBranchPairsName = (char*)malloc(30*numOfSelectedBranchPairs*sizeof(char));
char *siteSpecificBranchPairsIDs = (char*)malloc(25*numOfSelectedBranchPairs*sizeof(char));

// After:
char *siteSpecificBranchPairs = (char*)malloc((20*numOfSelectedBranchPairs+4)*sizeof(char));
char *siteSpecificBranchPairsName = (char*)malloc((30*numOfSelectedBranchPairs+4)*sizeof(char));
char *siteSpecificBranchPairsIDs = (char*)malloc((25*numOfSelectedBranchPairs+4)*sizeof(char));
```

---

### 6. VLA Off-by-One in outputDataInJS()

**File:** `src/JDKLabUtility.c`, `outputDataInJS()` function (around line 271)
**Symptom:** Stack buffer overflow on the VLA used for the output filename.
**Root cause:** `char temp[pos]` is one byte too small for the null terminator.
**Fix:** Change to `char temp[pos+1]` and explicitly null-terminate.

```c
// Before:
char temp[pos];
strncpy(temp, com.htmlFileName, pos);

// After:
char temp[pos+1];
strncpy(temp, com.htmlFileName, pos);
temp[pos] = '\0';
```

---

### 7. Undefined Behavior: Self-Referencing sprintf (14 instances)

**File:** `src/JDKLabUtility.c`, `outputDataInJS()` function (lines ~237-257, ~347-400)
**Symptom:** Output data JS file is empty or contains corrupted data, causing the interactive scatter plot to not render.
**Root cause:** `sprintf(buf, "%s...", buf, ...)` reads and writes to the same buffer, which is undefined behavior per the C standard. Some compilers/platforms produce correct results; others silently produce empty strings.
**Fix:** Replace all 14 instances with `sprintf(buf + strlen(buf), "...", ...)` which appends without overlapping source and destination.

```c
// Before (14 instances of this pattern):
sprintf(xPoints, "%s%.6f, ", xPoints, pDivergent[ig]);

// After:
sprintf(xPoints + strlen(xPoints), "%.6f, ", pDivergent[ig]);
```

**Affected variables:** `xPoints`, `yPoints`, `labels`, `xPostNumSub`, `ySiteClass`, `siteSpecificBranchPairs`, `siteSpecificBranchPairsName`, `siteSpecificBranchPairsIDs`, and `siteSpecificBP`.

---

### 8. Realloc Dangling Pointer in GetInitials()

**File:** `src/codeml.c`, inside `GetInitials()` (around line 2463)
**Symptom:** Segfault on Linux with >159 species. This was the fix in commit `4f9193e` that was already present before our session.
**Root cause:** After `realloc` of `conP` (and related buffers), the per-node `conP` pointers stored in the tree nodes become dangling. `PointconPnodes()` must be called to recompute them.
**Fix:** Call `PointconPnodes()` after the realloc block.

**Note for v2.0:** The dev version does NOT have this fix — it reallocs `conP`, `conP_part1`, `conP_prior`, `conP_byCat` without calling `PointconPnodes()` afterward.

---

## JavaScript / HTML Fixes

All JS fixes are in `assets/UI/assets/js/grand-conv.min.js` (the source file that gets copied to output by `gc-discover`). HTML template fixes are in `assets/UI/Template.html`.

### 9. Scatter Plot Mouseover Decoration Persistence

**Symptom:** When mousing over scatter plot points, the residual line, ellipse, and value label are drawn but never removed when the mouse leaves. Points accumulate decorations making the plot unusable.
**Root cause:** SVG.js `.front()` method does `removeChild()` + `insertBefore()` on DOM nodes, which causes the browser to lose pointer-element tracking. The `mouseout` event never fires on the original element.
**Fix (three layers):**

**Layer 1:** Add `pointer-events: none` to all decoration elements (resLine, resEllipse, resValue in scatter plot; branchEllipse, branchIdText in phylogram) so they don't intercept mouse events.

```js
// Added .style("pointer-events","none") to:
t.line(...).attr("id","resLine"+i).style("pointer-events","none")
t.ellipse(...).attr("id","resEllipse"+i).style("pointer-events","none")
t.text(...).attr("id","resValue"+i).style("pointer-events","none")
ph.drawing.ellipse(...).attr("id","branchEllipse"+a).style("pointer-events","none")
ph.drawing.text(...).attr("id","branchIdText"+a).style("pointer-events","none")
```

**Layer 2:** "Clean before decorate" pattern — at the start of every mouseover handler, remove any existing decorations left behind. Also add null-safe removal in the mouseout handler.

```js
// At start of mouseover handler I:
$("[id^='resLine']").remove();
$("[id^='resEllipse']").remove();
$("[id^='resValue']").remove();
$(".nodePtr").attr({rx:C/2,ry:C/2});  // reset radius (Layer 3)
updatePoints();

// Null-safe mouseout handler J:
var _el;
(_el=SVG.get("#resLine"+d))&&_el.remove();
(_el=SVG.get("#resEllipse"+d))&&_el.remove();
(_el=SVG.get("#resValue"+d))&&_el.remove();
```

**Layer 3:** Add cleanup handlers on the background rect (`u.on("mouseover",...)`) and SVG container (`t.on("mouseleave",...)`) to catch cases where the mouse leaves the plot area entirely.

---

### 10. Branch Pairs Table Cross-Window Communication Failure

**Symptom:** The Branch Pairs Table (sheet-index.html) opened as a popup cannot communicate with the main page. Mouseover on table rows doesn't highlight scatter plot points; clicking rows doesn't mark datapoints.
**Root cause:** The table uses `window.opener` to call functions on the parent window. Modern browsers block `window.opener` access for `file://` protocol pages (cross-origin restriction).
**Fix (two parts):**

**Part A — JS:** Add a smart fallback variable `_pw` and replace all 19 `window.opener.` references:

```js
// Added to global scope:
var _pw;
try{_pw=window.opener;_pw.document}catch(e){_pw=null}
if(!_pw)_pw=window;

// All window.opener.foo() calls changed to _pw.foo()
```

**Part B — Embed table inline:** Add `toggleTable()` function and a hidden `<div id="ssheet">` to the main page template, so the table renders in the same page instead of a popup.

```js
// Added to global scope:
var _tableDrawn=!1;
function toggleTable(){
  var s=document.getElementById("ssheet");
  s.style.display==="none"
    ?(s.style.display="block",_tableDrawn||(drawTable(),_tableDrawn=!0))
    :s.style.display="none"
}
```

**Template.html changes:**
- Changed `onclick="openSheetPopup()"` to `onclick="toggleTable()"`
- Added `<div id="ssheet" style="display:none; width:100%; margin-left:0px;"></div>` below the plot area

---

### 11. Invalid CSS Color "####" on Tooltip Ellipses

**Symptom:** Tooltip background behind residual values and branch ID text renders as black instead of a visible dark color.
**Root cause:** `"####"` is not a valid hex color. SVG.js parses it as rgb(0,0,0).
**Fix:** Replace with `"#444444"` (dark gray).

```js
// Before (2 occurrences):
.fill({color:"####"})

// After:
.fill({color:"#444444"})
```

**Locations:** scatterPlot mouseover handler (resEllipse), Phylogram.draw branch mouseover (branchEllipse).

---

### 12. Scatter Plot xMin/yMin Always Forced to Zero

**Symptom:** User-provided axis minimum values from `updateScatterPlot()` are silently ignored.
**Root cause:** Variables were initialized to `0` with the `d.xMin`/`d.yMin` values evaluated but discarded as dead expressions.

```js
// Before:
var j=0;d.xMin;var k=d.xMax,l=0;d.yMin;var m=d.yMax;
// j is always 0, so null==j never fires

// After:
var j=d.xMin,k=d.xMax,l=d.yMin,m=d.yMax;
// j is null when passed as null, so null==j fires correctly
```

**Same fix applied to `rateScatterPlot()`.**

---

### 13. Chrome Guard Inverted on DataTable Residual Updates

**Symptom:** When user edits slope/intercept, the DataTable's Residual column does not update in Chrome (the dominant browser).
**Root cause:** `null==window.chrome&&(...)` means "if NOT Chrome, register handlers." This is inverted.
**Fix:** Remove the Chrome guard entirely so handlers are always registered. Also added `calculateResiduals()` call inside the handlers so residuals are recalculated before updating the table.

```js
// Before:
null==window.chrome&&(_pw.$("#slopeInputField").change(...))

// After (guard removed, calculateResiduals added):
_pw.$("#slopeInputField").change(function(){
  calculateResiduals();
  for(var a=0;a<residuals.length;a++){...}
})
```

---

### 14. Phylogram Branch Mouseout Missing Null-Check

**Symptom:** TypeError crash when rapidly moving mouse across phylogram branches (mouseout fires before mouseover creates the tooltip elements).
**Root cause:** `SVG.get("#branchEllipse"+a).remove()` called without checking if `SVG.get()` returned null.
**Fix:** Add null-safe removal pattern.

```js
// Before:
SVG.get("#branchEllipse"+a).remove(),SVG.get("#branchIdText"+a).remove()

// After:
var _el;
(_el=SVG.get("#branchEllipse"+a))&&_el.remove();
(_el=SVG.get("#branchIdText"+a))&&_el.remove()
```

---

### 15. rateScatterPlot Missing tiptipCompSet Return Value

**Symptom:** After opening a Rate plot, clicking "Show Tip-tip" crashes with TypeError because `svgScatterPlot.tiptipCompSet` is undefined.
**Root cause:** `rateScatterPlot()` return object did not include `tiptipCompSet`.
**Fix:** Add an empty SVG set to the return value.

```js
// Before:
return{ylim:g,...,draw:v}

// After:
return{ylim:g,...,tiptipCompSet:v.set(),draw:v}
```

---

### 16. Dead Code in drawTable() — Ratio Overwritten by Residual

**Symptom:** No user-visible effect (dead code).
**Root cause:** `a[b][3]` is computed as a C:D ratio (with potential Infinity), then immediately overwritten with `residuals[b]`.
**Fix:** Remove the dead ratio computation.

```js
// Before:
a[b][3]=0!=xPoints[b]?yPoints[b]/xPoints[b]:1/0,a[b][3]=residuals[b]

// After:
a[b][3]=residuals[b]
```

---

### 17. regressionLine.front() Called Unconditionally

**Symptom:** Would crash if scatterPlot were called with `diag:false` (regression line not created).
**Root cause:** Three call sites assume `regressionLine` is always defined.
**Fix:** Guard with `regressionLine&&regressionLine.front()` at all three locations:
- `unhight_singleScatterPoint()`
- `unhighlight_scatterPoints_set()`
- `scatterPlot()` return statement

---

### 18. Blob URL Memory Leak in download()

**Symptom:** Blob URLs created for SVG export are never freed.
**Root cause:** `setTimeout(function(){window.URL.revokeObjectURL(this.href)},1500)` — inside the callback, `this` is `window`, not the download anchor. `this.href` is undefined.
**Fix:** Reference the closure variable directly instead of `this`.

```js
// Before:
setTimeout(function(){window.URL.revokeObjectURL(this.href)},1500)

// After (for downloadTree):
setTimeout(function(){window.URL.revokeObjectURL(downloadTree.href)},1500)
// (same pattern for downloadScatter)
```

---

### 19. rateScatterPlot X-Axis Tick Division by Zero

**Symptom:** If xMax < 10, x-axis ticks are spaced at Infinity, producing a broken axis.
**Root cause:** `Math.floor(l/10)` returns 0 when l < 10, then `(l-k)/0` = Infinity.
**Fix:** Ensure at least 1 tick division.

```js
// Before:
var B=Math.floor(l/10)

// After:
var B=Math.max(1,Math.floor(l/10))
```

---

### 20. Implicit Global Variables (Missing var Declarations)

**Symptom:** Variables leak into global scope, risking name collisions.
**Fixes applied:**

| Variable(s) | Location | Fix |
|---|---|---|
| `x1`, `y1` | `updateRegressionLine()` | Added `var x1,y1;` declaration before assignment |
| `circlesToBringToFront`, `crclIdx` | `rateScatterPlot()` | Changed to `var circlesToBringToFront=[],crclIdx=0;` |
| `pointLabel` | global scope | Added to existing `var ph,svgScatterPlot,...` declaration |
| `homePage` | `main()`, `generateRateVsDiversityPlot()`, `generateRateVsProbConvergencePlot()` | Removed entirely (assigned `this` which is just `window`, never used) |

---

### 21. Debug console.log Left in rateScatterPlot

**Symptom:** `circlesToBringToFront.length` logged to console on every rate plot render.
**Fix:** Removed the `console.log(circlesToBringToFront.length)` call.

---

### 22. Array Out-of-Bounds in generateRateVsDiversityPlot

**Symptom:** Potential TypeError crash (`f[h]` is undefined) when the site-specific data array `f` is shorter than the filtered site indices in `c`.
**Root cause:** The inner loop `for(;f[h][0]<i;)h++` advances `h` monotonically without checking if `h` has exceeded `f.length`.
**Fix:** Add bounds check and break.

```js
// Before:
for(var i=c[g];f[h][0]<i;)h++

// After:
for(var i=c[g];h<f.length&&f[h][0]<i;)h++;if(h>=f.length)break
```

---

### 23. download() Accumulates DOM Elements and Contains Dead Code

**Symptom:** Each Ctrl+click export appends two new `<a>` elements without removing old ones. Also, `document.querySelector("scatterOutput")` is evaluated via comma operator and discarded (no `<scatterOutput>` element exists).
**Fix:** Remove old `.dragout` elements before creating new ones. Remove dead `scatterOutput` querySelector.

```js
// Before:
var a=document.querySelector("treeOutput"),b=...

// After:
var a=document.querySelector("treeOutput");$(".dragout",a).remove();var b=...

// Also removed:
var d=(document.querySelector("scatterOutput"),svgScatterPlot.draw.exportSvg(...))
// Changed to:
var d=svgScatterPlot.draw.exportSvg(...)
```

---

### 24. Duplicate id="figure" in Template.html

**Symptom:** Two `<div>` elements share `id="figure"`, which is invalid HTML. `document.getElementById("figure")` would only find the first one.
**Fix:** Renamed to `id="figure-plot"` and `id="figure-tree"`.

---

### 25. Double `<body>` Tag in Template.html

**Symptom:** Template.html had `<body>` on line 21 and `<body onload='main()'>` on line 66 (inside the content area). Invalid HTML; browsers ignore the second tag but process its `onload`.
**Fix:** Moved `onload="main()"` to the real `<body>` tag on line 21. Replaced the second `<body>` with a plain `<div>`.

---

## Summary

| # | Category | File | Severity |
|---|---|---|---|
| 1 | C: Linker | paml.h | Build failure (GCC 10+) |
| 2 | C: Memory | codeml.c | Crash (segfault) |
| 3 | C: Memory | JDKLabUtility.c | Crash (segfault on large trees) |
| 4 | C: Memory | JDKLabUtility.c | Heap overflow |
| 5 | C: Memory | JDKLabUtility.c | Heap overflow |
| 6 | C: Memory | JDKLabUtility.c | Stack overflow |
| 7 | C: UB | JDKLabUtility.c | Missing plot data |
| 8 | C: Memory | codeml.c | Crash (>159 species) |
| 9 | JS: Events | grand-conv.min.js | Broken mouseover |
| 10 | JS/HTML | grand-conv.min.js + Template.html | Broken table interaction |
| 11 | JS: Rendering | grand-conv.min.js | Wrong tooltip color |
| 12 | JS: Logic | grand-conv.min.js | Ignored axis settings |
| 13 | JS: Logic | grand-conv.min.js | Feature broken in Chrome |
| 14 | JS: Crash | grand-conv.min.js | TypeError on fast mouse |
| 15 | JS: Crash | grand-conv.min.js | TypeError on tip-tip button |
| 16 | JS: Dead code | grand-conv.min.js | Minor (cleanup) |
| 17 | JS: Crash | grand-conv.min.js | Potential TypeError |
| 18 | JS: Leak | grand-conv.min.js | Memory leak |
| 19 | JS: Rendering | grand-conv.min.js | Broken axis ticks |
| 20 | JS: Globals | grand-conv.min.js | Namespace pollution |
| 21 | JS: Debug | grand-conv.min.js | Minor (cleanup) |
| 22 | JS: Crash | grand-conv.min.js | Potential TypeError |
| 23 | JS: Leak/Dead code | grand-conv.min.js | DOM accumulation |
| 24 | HTML: Invalid | Template.html | Duplicate IDs |
| 25 | HTML: Invalid | Template.html | Double body tag |
