<script setup>
defineProps({
  modelValue: Boolean,
  label: { type: String, default: '' },
  hint: { type: String, default: '' },
  disabled: Boolean,
})
defineEmits(['update:modelValue'])
</script>

<template>
  <div
    class="ui-toggle-row"
    :class="{ disabled }"
    role="switch"
    :aria-checked="modelValue"
    tabindex="0"
    @click="$emit('update:modelValue', !modelValue)"
    @keydown.space.prevent="$emit('update:modelValue', !modelValue)"
  >
    <div v-if="label || hint" class="t-text">
      <span v-if="label" class="t-label">{{ label }}</span>
      <span v-if="hint" class="t-hint">{{ hint }}</span>
    </div>
    <slot />
    <div class="ui-switch" :class="{ on: modelValue }"><div class="knob" /></div>
  </div>
</template>
