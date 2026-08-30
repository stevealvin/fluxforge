<script setup lang="ts">
import { computed, useTemplateRef, watch, onMounted, onBeforeUnmount } from 'vue'
import type * as monaco from 'monaco-editor'
import loader from '@monaco-editor/loader'
import { addExtraLibFromFetch, addExtraLibs, addGlobalSandboxTypes, detectLanguage } from './util'

interface Props {
  modelId?: string
  height?: string | number
  theme?: 'vs' | 'vs-dark' | 'hc-black'
  readOnly?: boolean
  language?: string
  autoDetectLanguage?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  modelId: 'main',
  height: '500px',
  theme: 'vs-dark',
  readOnly: false,
  language: 'javascript',
  autoDetectLanguage: true,
})

const modelValue = defineModel<string>()
  
const emit = defineEmits(['change', 'language-change'])

const codeStyle = computed(() => {
  if (typeof props.height === 'number') {
    return { height: `${props.height}px` }
  }
  return { height: props.height || '100%' }
})

const codeRef = useTemplateRef('codeRef')

let editor: monaco.editor.IStandaloneCodeEditor | null = null
let model: monaco.editor.ITextModel | null = null
let monacoInstance: typeof import('monaco-editor') | null = null
let hasAutoDetected = false

const init = async () => {
  const monaco: typeof import('monaco-editor') = await loader.init()
  monacoInstance = monaco

  const uri = monaco.Uri.parse(`file:///${props.modelId}.ts`)
  const existingModel = monaco.editor.getModel(uri)
  if (existingModel) {
    model = existingModel
    if (modelValue.value !== undefined && model.getValue() !== modelValue.value) {
      model.setValue(modelValue.value || '')
    }
  } else {
    model = monaco.editor.createModel(
      modelValue.value || '',
      props.language,
      uri
    )
  }
  
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
  addGlobalSandboxTypes(monaco)
  addExtraLibFromFetch(monaco, 'axios')
  addExtraLibFromFetch(monaco, 'cheerio')

  // 如果初始内容为特定语言（如 JSON / HTML），触发一次初始化识别
  if (props.autoDetectLanguage && modelValue.value) {
    const initialDetected = detectLanguage(modelValue.value)
    if (initialDetected && initialDetected !== props.language) {
      monaco.editor.setModelLanguage(model, initialDetected)
      hasAutoDetected = true
    }
  }

  addListener(monaco)
}

/** 设置编译选项 */
const setOptions = (monaco: typeof import('monaco-editor')) => {
  const compilerOptions = {
    checkJs: true,
    allowJs: true,
    strict: true,
    esModuleInterop: true,
    moduleResolution: monaco.typescript.ModuleResolutionKind.NodeJs,
    module: monaco.typescript.ModuleKind.ESNext,
    target: monaco.typescript.ScriptTarget.ESNext,
  }

  monaco.typescript.javascriptDefaults.setDiagnosticsOptions({
    noSemanticValidation: false,
    noSyntaxValidation: false,
  })
  monaco.typescript.javascriptDefaults.setCompilerOptions(compilerOptions)

  monaco.typescript.typescriptDefaults.setDiagnosticsOptions({
    noSemanticValidation: false,
    noSyntaxValidation: false,
  })
  monaco.typescript.typescriptDefaults.setCompilerOptions(compilerOptions)
}

/** 添加快捷键指令 */
const addCommands = (monaco: typeof import('monaco-editor')) => {
  // editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyQ, () => {
  //   editor.trigger('keyboard', 'editor.action.triggerSuggest', {})
  // })
}

/** 设置监听事件 */
const addListener = (monaco: typeof import('monaco-editor')) => {
  if (!editor) return

  // 监听内容变化
  editor.onDidChangeModelContent(() => {
    if (!editor || !model) return
    const value = editor.getValue()
    // 避免循环更新：只有当值确实变化时才 emit
    if (value !== modelValue.value) {
      modelValue.value = value
      emit('change', value)
    }

    // 智能语言自动识别（仅在启用 autoDetectLanguage 时触发）
    if (props.autoDetectLanguage) {
      const trimmed = value.trim()
      // 若内容被清空，重置识别锁，允许下一次输入重新识别
      if (!trimmed) {
        hasAutoDetected = false
        return
      }

      // 仅在首次输入/粘贴且未锁定时识别一次
      if (!hasAutoDetected && trimmed.length >= 4) {
        const detected = detectLanguage(trimmed)
        if (detected && detected !== props.language) {
          monaco.editor.setModelLanguage(model, detected)
          hasAutoDetected = true
          emit('language-change', detected)
        }
      }
    }
  })
}

watch(() => modelValue.value, (newValue) => {
  if (!model || !editor) return
  const currentValue = editor.getValue()
  // 只有当外部值与编辑器当前值不同时才更新，避免光标跳动
  if (newValue !== currentValue) {
    editor.setValue(newValue || '')
  }
})

watch(() => props.theme, (newTheme) => {
  if (editor && newTheme) {
    editor.updateOptions({ theme: newTheme })
  }
})

watch(() => props.language, (newLang) => {
  if (newLang && model && monacoInstance) {
    monacoInstance.editor.setModelLanguage(model, newLang)
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

<style scoped>
.code-viewport {
  width: 100%;
  height: 100%;
}
</style>