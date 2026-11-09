// Executes the production Kotlin raw-string script, not a second implementation.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../../main/java/com/green/note/content/BrowserScreen.kt'),'utf8');
const template=source.match(/internal fun activityThemeScript\(dark: Boolean\): String = """([\s\S]*?)"""\.trimIndent\(\)/)[1];
const darkRule={media:{mediaText:'screen and (min-width: 600px) and (prefers-color-scheme: dark)'}};
const lightRule={media:{mediaText:'(prefers-color-scheme: light) and (orientation: landscape)'}};
const child={media:{mediaText:'(prefers-color-scheme: DARK)'}};
const unrelated={media:{mediaText:'print and (min-width: 500px)'}};
const blocked={get cssRules(){throw new Error('cross-origin stylesheet');}};
const rules=[darkRule,lightRule,{cssRules:[child]},unrelated];
const context={window:{},document:{styleSheets:[blocked,{cssRules:rules}]},WeakMap};
function apply(dark){vm.runInNewContext(template.replace('${if (dark) "dark" else "light"}',dark?'dark':'light'),context);}
for(const dark of [false,true,false,true]){
 apply(dark);
 assert.equal(darkRule.media.mediaText,`screen and (min-width: 600px) and (min-width: ${dark?0:2147483647}px)`);
 assert.equal(lightRule.media.mediaText,`(min-width: ${dark?2147483647:0}px) and (orientation: landscape)`);
 assert.equal(child.media.mediaText,`(min-width: ${dark?0:2147483647}px)`);
 assert.equal(unrelated.media.mediaText,'print and (min-width: 500px)');
}
const inserted={media:{mediaText:'(prefers-color-scheme: light)'}};rules.push(inserted);apply(false);
assert.equal(inserted.media.mediaText,'(min-width: 0px)');
assert.equal(darkRule.media.mediaText,'screen and (min-width: 600px) and (min-width: 2147483647px)');
console.log('PASS: production theme script, four theme switches, preserved conditions, nested/dynamic rules, cross-origin isolation');
