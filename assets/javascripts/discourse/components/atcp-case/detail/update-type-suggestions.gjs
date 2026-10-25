<template>
  <datalist id={{@id}} ...attributes>
    {{#each @labels as |label|}}
      <option value={{label}}></option>
    {{/each}}
  </datalist>
</template>
