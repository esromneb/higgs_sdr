#args
shows passing in-html args to partials

```
<template name="logPartial">
<em>c</em>: {{c}} {{log_title}}
</template>

<template name="allLogs">
<table>
<tr>
<td>
<div class="logs_box" id="log_0">{{#each logs_0}}{{> logPartial log_title='foo'}}{{/each}}</div>
</td>
<td>
<div class="logs_box" id="log_1">{{> logPartial }}</div>
</td>
<td>
<div class="logs_box" id="log_2">{{logs_2}}</div>
</td>
</tr>
</table>

</template>

```