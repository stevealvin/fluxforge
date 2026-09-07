<script setup lang="ts">
import { ref, computed, watch, h } from 'vue'
import { useMessage, NTag } from 'naive-ui'
import { useAiSettingsStore, AI_PRESETS, type AiProfile } from '@/stores/aiSettings'
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
  RefreshCw,
  Plus,
  Copy,
  Trash2,
  Check,
  Edit3
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

// 当前在设置弹窗中选中的编辑配置 ID
const editingProfileId = ref<string>('')

// 本地表单状态（纯配置数据字段，不含 ID，避免主键混淆）
const form = ref({
  name: '',
  provider: 'openai',
  baseUrl: '',
  apiKey: '',
  model: '',
  temperature: 0.1
})

// 将当前表单有效配置数据同步至 Store 对应的 Profile
const syncCurrentFormToStore = (targetId: string = editingProfileId.value) => {
  if (!targetId) return
  aiStore.updateProfile(targetId, {
    name: form.value.name,
    provider: form.value.provider,
    baseUrl: form.value.baseUrl,
    apiKey: form.value.apiKey,
    model: form.value.model,
    temperature: form.value.temperature
  })
}

// 加载指定 Profile 到本地表单进行编辑
const loadProfileToForm = (profileId: string) => {
  const p = aiStore.profiles.find((item) => item.id === profileId) || aiStore.profiles[0]
  if (p) {
    editingProfileId.value = p.id
    form.value = {
      name: p.name,
      provider: p.provider,
      baseUrl: p.baseUrl,
      apiKey: p.apiKey,
      model: p.model,
      temperature: p.temperature
    }
    testStatus.value = null
  }
}

// 弹窗打开或 Store 初始化时同步激活项
watch(
  () => props.show,
  (visible) => {
    if (visible) {
      loadProfileToForm(aiStore.activeProfileId)
    }
  },
  { immediate: true }
)

// 切换正在编辑的配置项（严格按先存旧、后载新顺序执行，彻底消除竞态覆盖）
const handleSelectProfile = (newId: string) => {
  if (!newId || newId === editingProfileId.value) return
  // 1. 先将离开前旧配置的修改安全同步到 Store
  syncCurrentFormToStore(editingProfileId.value)
  // 2. 载入新选中的配置内容到表单
  loadProfileToForm(newId)
}

// 将当前正在编辑的配置设为全局生效 (激活)
const handleSetActive = () => {
  if (!editingProfileId.value) return
  // 先同步表单
  syncCurrentFormToStore(editingProfileId.value)
  aiStore.setActiveProfile(editingProfileId.value)
  message.success(`已将「${form.value.name || '当前配置'}」设为全局生效模型`)
}

// 快速新建配置菜单选项
const addPresetDropdownOptions = [
  { label: 'DeepSeek 官方预设 (推荐)', key: 'preset_deepseek' },
  { label: 'Google Gemini 2.0 (原生REST)', key: 'preset_gemini' },
  { label: 'Anthropic Claude 3.5 (原生API)', key: 'preset_claude' },
  { label: 'OpenAI 兼容协议自定义', key: 'preset_openai' }
]

// 处理新建配置
const handleAddProfile = (key: string) => {
  // 先安全暂存当前表单输入
  syncCurrentFormToStore(editingProfileId.value)

  let newProfile: AiProfile
  if (key === 'preset_deepseek') {
    newProfile = aiStore.addProfile('openai', 'DeepSeek 官方')
    aiStore.updateProfile(newProfile.id, {
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-chat'
    })
  } else if (key === 'preset_gemini') {
    newProfile = aiStore.addProfile('gemini', 'Google Gemini 2.0')
    aiStore.updateProfile(newProfile.id, {
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      model: 'gemini-2.0-flash'
    })
  } else if (key === 'preset_claude') {
    newProfile = aiStore.addProfile('claude', 'Claude 3.5 Sonnet')
    aiStore.updateProfile(newProfile.id, {
      baseUrl: 'https://api.anthropic.com/v1',
      model: 'claude-3-5-sonnet-20241022'
    })
  } else {
    newProfile = aiStore.addProfile('openai', '自定义 OpenAI 接口')
  }

  loadProfileToForm(newProfile.id)
  message.success(`已创建新配置「${newProfile.name}」`)
}

// 复制当前配置为副本
const handleDuplicateProfile = () => {
  // 先同步保存当前编辑项内容
  syncCurrentFormToStore(editingProfileId.value)

  // 克隆生成独立的新副本并加载
  const duplicated = aiStore.duplicateProfile(editingProfileId.value)
  if (duplicated) {
    loadProfileToForm(duplicated.id)
    message.success(`已克隆创建配置「${duplicated.name}」`)
  }
}

// 删除当前配置
const handleDeleteProfile = () => {
  if (aiStore.profiles.length <= 1) {
    message.warning('系统必须保留至少一个 AI 配置')
    return
  }
  const currentName = form.value.name
  const idToDelete = editingProfileId.value
  const success = aiStore.deleteProfile(idToDelete)
  if (success) {
    message.success(`已删除配置「${currentName}」`)
    loadProfileToForm(aiStore.activeProfileId)
  }
}

// Profile 下拉选择项生成（展示名称、协议与生效标签）
const profileSelectOptions = computed(() => {
  return aiStore.profiles.map((p) => {
    const isActive = p.id === aiStore.activeProfileId
    return {
      label: p.name || '未命名配置',
      value: p.id,
      isActive,
      provider: p.provider
    }
  })
})

// 自定义渲染 Profile 下拉选项
const renderProfileOptionLabel = (option: any) => {
  return h(
    'div',
    { class: 'flex items-center justify-between w-full py-0.5 gap-2' },
    [
      h('div', { class: 'flex items-center gap-2 truncate' }, [
        h('span', { class: 'font-bold text-xs truncate' }, option.label),
        h(
          'span',
          { class: 'text-[10px] text-zinc-400 font-mono px-1.5 py-0.2 rounded bg-zinc-100 dark:bg-white/5' },
          option.provider
        )
      ]),
      option.isActive
        ? h(
            NTag,
            { type: 'success', size: 'tiny', round: true, bordered: false, class: '!text-[10px] !font-bold' },
            { default: () => '生效中' }
          )
        : null
    ]
  )
}

const presetOptions = computed(() => {
  return Object.entries(AI_PRESETS).map(([key, item]) => ({
    label: item.label,
    value: key
  }))
})

// 模型列表：若已通过接口获取则展示获取到的列表，否则展示该协议默认的最新主流模型
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

// 测试连通性（支持直接传入当前正在编辑的表单状态测试）
const handleTestConnection = async () => {
  testing.value = true
  testStatus.value = null

  try {
    const res = await aiStore.testConnection(form.value)
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

// 保存所有配置
const handleSave = () => {
  syncCurrentFormToStore()
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
    class="!rounded-3xl max-w-2xl shadow-2xl"
    :segmented="{ content: 'soft', footer: 'soft' }"
  >
    <template #header>
      <div class="flex items-center gap-2.5">
        <div class="w-8 h-8 rounded-xl bg-gradient-to-tr from-emerald-600 via-teal-500 to-cyan-500 flex items-center justify-center shadow-md shadow-emerald-500/20 text-white">
          <Settings class="w-4 h-4" />
        </div>
        <div>
          <h2 class="text-base font-black text-zinc-900 dark:text-white">系统偏好与 AI 模型设置</h2>
          <p class="text-[11px] text-zinc-400">支持配置并随心切换多个大模型 API 节点 (DeepSeek, Gemini, OpenAI 等)</p>
        </div>
      </div>
    </template>

    <div class="space-y-4">
      <!-- 选项卡导航 -->
      <div class="flex items-center gap-2 p-1 bg-zinc-100 dark:bg-white/[0.04] rounded-2xl">
        <button
          type="button"
          @click="activeTab = 'ai'"
          class="flex-1 py-1.5 px-3 rounded-xl text-xs font-bold transition-all flex items-center justify-center gap-2 cursor-pointer"
          :class="activeTab === 'ai' ? 'bg-white dark:bg-zinc-800 text-emerald-600 dark:text-emerald-400 shadow-xs' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'"
        >
          <Bot class="w-3.5 h-3.5" />
          <span>AI 规则助手模型 (多API配置)</span>
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

      <!-- Tab 1: AI 模型多配置管理与编辑 -->
      <div v-if="activeTab === 'ai'" class="space-y-4">
        <!-- 顶部 Profile 管理控制台 -->
        <div class="p-3 rounded-2xl bg-zinc-50 dark:bg-white/[0.03] border border-zinc-200/70 dark:border-white/5 space-y-2.5 shadow-2xs">
          <div class="flex items-center justify-between text-xs">
            <span class="font-bold text-zinc-700 dark:text-zinc-300 flex items-center gap-1.5">
              <Bot class="w-3.5 h-3.5 text-emerald-500" />
              <span>选择/管理 API 配置方案:</span>
            </span>

            <!-- 生效状态标签或设为生效按钮 -->
            <div class="flex items-center gap-2">
              <n-tag
                v-if="editingProfileId === aiStore.activeProfileId"
                type="success"
                size="small"
                round
                :bordered="false"
                class="!font-bold !text-[11px] flex items-center gap-1"
              >
                <template #icon>
                  <Check class="w-3 h-3 text-emerald-500" />
                </template>
                当前全局生效中
              </n-tag>
              <n-button
                v-else
                size="tiny"
                secondary
                type="primary"
                class="!rounded-lg !font-bold !text-[11px]"
                @click="handleSetActive"
              >
                <template #icon>
                  <Check class="w-3 h-3" />
                </template>
                设为当前生效
              </n-button>
            </div>
          </div>

          <!-- 配置切换下拉与操作按钮组 -->
          <div class="flex items-center gap-2">
            <n-select
              :value="editingProfileId"
              :options="profileSelectOptions"
              :render-label="renderProfileOptionLabel"
              @update:value="handleSelectProfile"
              class="flex-1 !rounded-xl text-xs font-bold"
            />

            <!-- 克隆配置 -->
            <n-button
              size="small"
              secondary
              class="!rounded-xl shrink-0"
              @click="handleDuplicateProfile"
              title="克隆此配置创建副本"
            >
              <template #icon>
                <Copy class="w-3.5 h-3.5 text-zinc-500" />
              </template>
              <span>克隆</span>
            </n-button>

            <!-- 新建配置下拉菜单 -->
            <n-dropdown
              trigger="click"
              :options="addPresetDropdownOptions"
              @select="handleAddProfile"
            >
              <n-button
                size="small"
                type="primary"
                secondary
                class="!rounded-xl !font-bold shrink-0"
              >
                <template #icon>
                  <Plus class="w-3.5 h-3.5" />
                </template>
                <span>新建配置</span>
              </n-button>
            </n-dropdown>

            <!-- 删除配置 -->
            <n-popconfirm
              v-if="aiStore.profiles.length > 1"
              positive-text="确认删除"
              negative-text="取消"
              @positive-click="handleDeleteProfile"
            >
              <template #trigger>
                <n-button
                  size="small"
                  quaternary
                  type="error"
                  class="!rounded-xl shrink-0"
                  title="删除当前配置"
                >
                  <template #icon>
                    <Trash2 class="w-3.5 h-3.5" />
                  </template>
                </n-button>
              </template>
              确定删除配置「{{ form.name }}」吗？
            </n-popconfirm>
          </div>
        </div>

        <!-- 当前配置详情编辑表单 -->
        <div class="space-y-3.5 pt-1">
          <!-- 配置备注名称 -->
          <div class="space-y-1.5">
            <label class="text-xs font-bold text-zinc-700 dark:text-zinc-300 flex items-center justify-between">
              <span class="flex items-center gap-1.5">
                <Edit3 class="w-3.5 h-3.5 text-indigo-500" />
                <span>配置备注名称 (Profile Name)</span>
              </span>
              <span class="text-[11px] font-normal text-zinc-400">例如：DeepSeek 官方、Gemini 2.0 备用</span>
            </label>
            <n-input
              v-model:value="form.name"
              placeholder="请输入配置名称"
              class="!rounded-xl text-xs font-bold"
            />
          </div>

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
            <p class="text-[11px] text-zinc-400">密钥保存在您本地浏览器的 localStorage 中，不同配置相互隔离，绝不上传第三方服务器。</p>
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
