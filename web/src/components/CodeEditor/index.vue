<script setup lang="ts">
import { computed, useTemplateRef, watch, onMounted, onBeforeUnmount } from 'vue'
import * as monaco from 'monaco-editor'
import loader from '@monaco-editor/loader'
import { addExtraLibFromFetch, addExtraLibs } from './util'

interface Props {
  modelId?: string
  height?: string | number
  theme?: 'vs' | 'vs-dark' | 'hc-black'
  readOnly?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  modelId: 'main',
  height: '500px',
  theme: 'vs-dark',
  readOnly: false,
})

const modelValue = defineModel<string>()
  
const emit = defineEmits(['change'])

const codeStyle = computed(() => {
  if (typeof props.height === 'number') {
    return { height: `${props.height}px` }
  }
  return { height: props.height || '100%' }
})

const codeRef = useTemplateRef('codeRef')

let editor: monaco.editor.IStandaloneCodeEditor | null = null
let model: monaco.editor.ITextModel | null = null

const init = async () => {
  const monaco: typeof import('monaco-editor') = await loader.init()

  const uri = monaco.Uri.parse(`file:///${props.modelId}.ts`)
  model = monaco.editor.createModel(
    modelValue.value || '',
    'javascript',
    uri
  )
  
  editor = monaco.editor.create(codeRef.value!, {
    model,
    theme: props.theme,
    automaticLayout: true,
    readOnly: props.readOnly,
    minimap: {
      enabled: false
    },
    tabSize: 2,
    fontSize: 14,
  } as monaco.editor.IStandaloneEditorConstructionOptions)

  setOptions(monaco)
  addCommands(monaco)

  // 添加类型定义
  addExtraLibFromFetch(monaco, 'axios')
  addExtraLibFromFetch(monaco, 'cheerio')

  addListener()
}

/** 设置编译选项 */
const setOptions = (monaco: typeof import('monaco-editor')) => {
  monaco.typescript.javascriptDefaults.setDiagnosticsOptions({
    noSemanticValidation: false,
    noSyntaxValidation: false,
  })

  monaco.typescript.javascriptDefaults.setCompilerOptions({
    checkJs: true,
    allowJs: true,
    strict: true,
    esModuleInterop: true,
    moduleResolution: monaco.typescript.ModuleResolutionKind.NodeJs,
    module: monaco.typescript.ModuleKind.ESNext,
    target: monaco.typescript.ScriptTarget.ESNext,
  })
}

/** 添加快捷键指令 */
const addCommands = (monaco: typeof import('monaco-editor')) => {
  // editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyQ, () => {
  //   editor.trigger('keyboard', 'editor.action.triggerSuggest', {})
  // })
}

/** 设置监听事件 */
const addListener = () => {
  // 监听内容变化
  editor.onDidChangeModelContent(e => {
    const value = editor.getValue()
    // 避免循环更新：只有当值确实变化时才 emit
    if (value !== modelValue.value) {
      modelValue.value = value
      emit('change', value)
    }
  })
}

watch(() => modelValue.value, (newValue) => {
  if (!model || !editor) return
  const currentValue = editor.getValue()
  // 只有当外部值与编辑器当前值不同时才更新，避免光标跳动
  if (newValue !== currentValue) {
    editor.setValue(newValue)
  }
})

watch(() => props.theme, (newTheme) => {
  if (editor && newTheme) {
    editor.updateOptions({ theme: newTheme })
  }
})

onMounted(() => {
  init()
})

onBeforeUnmount(() => {
  model?.dispose()
  editor?.dispose()
})

// 暴露方法给父组件
defineExpose({
  // 获取编辑器实例
  getEditor: () => editor,
  // 获取编辑器内容
  getValue: () => editor?.getValue() || '',
  // 设置编辑器内容
  setValue: (value: string) => editor?.setValue(value),
  // 焦点
  focus: () => editor?.focus(),
  // 格式化代码
  format: () => {
    if (editor) {
      editor.getAction('editor.action.formatDocument')?.run()
    }
  }
})
</script>

<template>
  <div ref="codeRef" class="code-viewport w-full" :style="codeStyle"></div>
</template>

<style>
.code-viewport {
  height: 300px;
  .cm-editor {
    border: 1px solid #ddd;
  }

  .cm-scroller {
    overflow: auto;
  }
}
.placeholder {
  position: absolute;
  top: 12px;
  left: 12px;
  color: #6b7280;
  pointer-events: auto;
  cursor: text;
  font-size: 14px;
  user-select: none;
}
</style>