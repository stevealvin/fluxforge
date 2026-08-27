<script setup lang="ts">
import { ref, computed } from 'vue'
import { useMessage } from 'naive-ui'
import { useAiSettingsStore, AI_PRESETS } from '@/stores/aiSettings'
import {
  Settings,
  Bot,
  Key,
  Globe,
  Sliders,
  CheckCircle2,
  AlertCircle,
  Sparkles,
  Zap,
  RefreshCw
} from '@lucide/vue'

const props = defineProps<{
  show: boolean
}>()

const emit = defineEmits<{
  (e: 'update:show', value: boolean): void
}>()

const message = useMessage()
const aiStore = useAiSettingsStore()

const activeTab = ref<'ai' | 'about'>('ai')
const testing = ref(false)
const testStatus = ref<{ success?: boolean; message?: string } | null>(null)

const fetchingModels = ref(false)
const remoteModelsMap = ref<Record<string, string[]>>({})

// 本地表单状态
const form = ref({
  provider: aiStore.provider,
  baseUrl: aiStore.baseUrl,
  apiKey: aiStore.apiKey,
  model: aiStore.model,
  temperature: aiStore.temperature
})

const presetOptions = computed(() => {
  return Object.entries(AI_PRESETS).map(([key, item]) => ({
    label: item.label,
    value: key
  }))
})

// 模型列表：若已通过接口获取则展示获取到的列表，否则展示该协议默认的 2 个最新主流模型
const availableModels = computed(() => {
  const customList = remoteModelsMap.value[form.value.provider]
  if (customList && customList.length > 0) {
    return customList.map((m) => ({ label: m, value: m }))
  }
  const preset = AI_PRESETS[form.value.provider]
  return preset?.models?.map((m) => ({ label: m, value: m })) || []
})

const handleProviderChange = (val: string) => {
  form.value.provider = val
  const preset = AI_PRESETS[val]
  if (preset) {
    form.value.baseUrl = preset.baseUrl
    form.value.model = preset.defaultModel
  }
}

// 动态通过接口从厂商拉取模型列表
const handleFetchModels = async () => {
  if (!form.value.baseUrl) {
    message.warning('请先填写 API 接口地址 (Base URL)')
    return
  }

  fetchingModels.value = true
  try {
    const list = await aiStore.fetchRemoteModels(form.value)
    if (list && list.length > 0) {
      remoteModelsMap.value[form.value.provider] = list
      if (!list.includes(form.value.model)) {
        form.value.model = list[0]
      }
      message.success(`成功从接口拉取 ${list.length} 个模型！`)
    } else {
      message.warning('未能获取到有效模型列表')
    }
  } catch (err: any) {
    message.error(err.message || '获取模型列表失败')
  } finally {
    fetchingModels.value = false
  }
}

const handleTestConnection = async () => {
  // 先同步临时表单
  aiStore.saveSettings(form.value)
  testing.value = true
  testStatus.value = null

  try {
    const res = await aiStore.testConnection()
    testStatus.value = res
    if (res.success) {
      message.success(res.message)
    } else {
      message.error(res.message)
    }
  } catch (err: any) {
    testStatus.value = { success: false, message: err.message }
    message.error('测试异常: ' + err.message)
  } finally {
    testing.value = false
  }
}

const handleSave = () => {
  aiStore.saveSettings(form.value)
  message.success('AI 模型配置已保存')
  emit('update:show', false)
}
</script>

<template>
  <n-modal
    :show="show"
    @update:show="(val) => emit('update:show', val)"
    preset="card"
    title="系统设置"
    class="!rounded-3xl max-w-xl shadow-2xl"
    :segmented="{ content: 'soft', footer: 'soft' }"
  >
    <template #header>
      <div class="flex items-center gap-2.5">
        <div class="w-8 h-8 rounded-xl bg-gradient-to-tr from-emerald-600 via-teal-500 to-cyan-500 flex items-center justify-center shadow-md shadow-emerald-500/20 text-white">
          <Settings class="w-4 h-4" />
        </div>
        <div>
          <h2 class="text-base font-black text-zinc-900 dark:text-white">系统偏好与 AI 模型设置</h2>
          <p class="text-[11px] text-zinc-400">配置用于智能规则生成与自动代码辅助的 LLM 大模型</p>
        </div>
      </div>
    </template>

    <div class="space-y-5">
      <!-- 选项卡导航 -->
      <div class="flex items-center gap-2 p-1 bg-zinc-100 dark:bg-white/[0.04] rounded-2xl">
        <button
          type="button"
          @click="activeTab = 'ai'"
          class="flex-1 py-1.5 px-3 rounded-xl text-xs font-bold transition-all flex items-center justify-center gap-2 cursor-pointer"
          :class="activeTab === 'ai' ? 'bg-white dark:bg-zinc-800 text-emerald-600 dark:text-emerald-400 shadow-xs' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'"
        >
          <Bot class="w-3.5 h-3.5" />
          <span>AI 规则助手模型</span>
        </button>
        <button
          type="button"
          @click="activeTab = 'about'"
          class="flex-1 py-1.5 px-3 rounded-xl text-xs font-bold transition-all flex items-center justify-center gap-2 cursor-pointer"
          :class="activeTab === 'about' ? 'bg-white dark:bg-zinc-800 text-emerald-600 dark:text-emerald-400 shadow-xs' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'"
        >
          <Sparkles class="w-3.5 h-3.5" />
          <span>关于 FluxForge</span>
        </button>
      </div>

      <!-- Tab 1: AI 模型配置 -->
      <div v-if="activeTab === 'ai'" class="space-y-4">
        <!-- 厂商预设选择 -->
        <div class="space-y-1.5">
          <label class="text-xs font-bold text-zinc-700 dark:text-zinc-300 flex items-center gap-1.5">
            <Zap class="w-3.5 h-3.5 text-emerald-500" />
            <span>API 协议类型 / 模型厂商</span>
          </label>
          <n-select
            v-model:value="form.provider"
            :options="presetOptions"
            @update:value="handleProviderChange"
            class="!rounded-xl"
          />
          <p v-if="AI_PRESETS[form.provider]?.desc" class="text-[11px] text-zinc-400 leading-relaxed">
            {{ AI_PRESETS[form.provider].desc }}
          </p>
        </div>

        <!-- Base URL -->
        <div class="space-y-1.5">
          <label class="text-xs font-bold text-zinc-700 dark:text-zinc-300 flex items-center gap-1.5">
            <Globe class="w-3.5 h-3.5 text-teal-500" />
            <span>API 接口地址 (Base URL)</span>
          </label>
          <n-input
            v-model:value="form.baseUrl"
            :placeholder="AI_PRESETS[form.provider]?.baseUrl || '例如: https://api.openai.com/v1'"
            class="!rounded-xl font-mono text-xs"
          />
        </div>

        <!-- API Key -->
        <div class="space-y-1.5">
          <label class="text-xs font-bold text-zinc-700 dark:text-zinc-300 flex items-center gap-1.5">
            <Key class="w-3.5 h-3.5 text-amber-500" />
            <span>API 访问密钥 (API Key)</span>
          </label>
          <n-input
            v-model:value="form.apiKey"
            type="password"
            show-password-on="click"
            placeholder="sk-..."
            class="!rounded-xl font-mono text-xs"
          />
          <p class="text-[11px] text-zinc-400">密钥仅安全保存在您本地浏览器的 localStorage 中，绝不会上传第三方服务器。</p>
        </div>

        <!-- 模型名称 (可选择、可直接输入) -->
        <div class="space-y-1.5">
          <label class="text-xs font-bold text-zinc-700 dark:text-zinc-300 flex items-center justify-between">
            <span class="flex items-center gap-1.5">
              <Bot class="w-3.5 h-3.5 text-cyan-500" />
              <span>模型名称 (Model)</span>
            </span>
            <span class="text-[11px] font-normal text-zinc-400">支持下拉选择或直接键入自定义模型</span>
          </label>
          <div class="flex items-center gap-2">
            <n-select
              v-model:value="form.model"
              :options="availableModels"
              filterable
              tag
              :placeholder="`请选择或输入模型名称，默认: ${AI_PRESETS[form.provider]?.defaultModel || 'gpt-4o-mini'}`"
              class="!rounded-xl font-mono text-xs flex-1"
            />

            <!-- 获取模型按钮 (实时通过 API 接口拉取) -->
            <n-button
              size="small"
              secondary
              type="primary"
              :loading="fetchingModels"
              class="!rounded-xl !font-bold shrink-0"
              @click="handleFetchModels"
              title="根据当前 API 接口实时获取可用模型列表"
            >
              <template #icon>
                <RefreshCw class="w-3.5 h-3.5" :class="{ 'animate-spin': fetchingModels }" />
              </template>
              <span>获取模型</span>
            </n-button>
          </div>
        </div>

        <!-- 采样温度 Temperature -->
        <div class="space-y-1.5 pt-1">
          <div class="flex items-center justify-between text-xs font-bold text-zinc-700 dark:text-zinc-300">
            <span class="flex items-center gap-1.5">
              <Sliders class="w-3.5 h-3.5 text-emerald-500" />
              <span>温度系数 (Temperature)</span>
            </span>
            <span class="font-mono text-emerald-600 dark:text-emerald-400">{{ form.temperature }}</span>
          </div>
          <n-slider
            v-model:value="form.temperature"
            :step="0.05"
            :min="0"
            :max="1"
          />
          <p class="text-[11px] text-zinc-400">编写代码建议设置为 0.1，以获取更精准严格的解析语法结构。</p>
        </div>

        <!-- 测试状态反馈 -->
        <div
          v-if="testStatus"
          class="p-3 rounded-xl text-xs flex items-center gap-2"
          :class="testStatus.success ? 'bg-emerald-50 dark:bg-emerald-950/40 text-emerald-600 dark:text-emerald-400 border border-emerald-200/50' : 'bg-rose-50 dark:bg-rose-950/40 text-rose-600 dark:text-rose-400 border border-rose-200/50'"
        >
          <CheckCircle2 v-if="testStatus.success" class="w-4 h-4 flex-shrink-0" />
          <AlertCircle v-else class="w-4 h-4 flex-shrink-0" />
          <span class="leading-relaxed">{{ testStatus.message }}</span>
        </div>
      </div>

      <!-- Tab 2: 关于 FluxForge -->
      <div v-else-if="activeTab === 'about'" class="space-y-3 py-2 text-xs leading-relaxed text-zinc-600 dark:text-zinc-400">
        <div class="p-4 rounded-2xl bg-emerald-50/60 dark:bg-emerald-950/30 border border-emerald-200/40 dark:border-emerald-800/30 space-y-2">
          <div class="flex items-center gap-2 font-bold text-emerald-700 dark:text-emerald-300 text-sm">
            <Sparkles class="w-4 h-4 text-emerald-500" />
            <span>FluxForge 多媒体聚合与沙箱规则引擎</span>
          </div>
          <p>
            基于 Node.js VM 沙箱架构与 Cheerio/Axios 驱动，支持跨站点多媒体（视频、图片、小说）的高性能发现、聚合搜索与动态直链提取。
          </p>
        </div>
        <div class="grid grid-cols-2 gap-2 pt-2">
          <div class="p-3 rounded-xl border border-zinc-200/60 dark:border-white/5 space-y-1">
            <div class="font-bold text-zinc-800 dark:text-zinc-200">当前版本</div>
            <div class="font-mono text-zinc-500">v2.1.0 (FluxForge)</div>
          </div>
          <div class="p-3 rounded-xl border border-zinc-200/60 dark:border-white/5 space-y-1">
            <div class="font-bold text-zinc-800 dark:text-zinc-200">引擎内核</div>
            <div class="font-mono text-zinc-500">Node VM Sandbox</div>
          </div>
        </div>
      </div>
    </div>

    <!-- 底部按钮 -->
    <template #footer>
      <div class="flex items-center justify-between gap-3">
        <n-button
          v-if="activeTab === 'ai'"
          secondary
          size="small"
          :loading="testing"
          @click="handleTestConnection"
          class="!rounded-xl !font-bold"
        >
          测试连通性
        </n-button>
        <div v-else></div>

        <div class="flex items-center gap-2">
          <n-button size="small" class="!rounded-xl" @click="emit('update:show', false)">
            取消
          </n-button>
          <n-button
            type="primary"
            size="small"
            class="!rounded-xl !font-bold"
            @click="handleSave"
          >
            保存配置
          </n-button>
        </div>
      </div>
    </template>
  </n-modal>
</template>

<style scoped>
</style>
