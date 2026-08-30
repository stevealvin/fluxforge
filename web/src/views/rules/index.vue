<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'

defineOptions({ name: 'RulesView' })
import { useMessage } from 'naive-ui'
import { ruleService, type RuleSchema } from '@/utils/ruleService'
import {
  RefreshCcw,
  Search as SearchIcon,
  Plus,
  Edit as EditIcon,
  Trash2,
  Download,
  Upload,
  Copy,
  Archive,
  Compass,
  Video,
  Image as ImageIcon,
  BookOpen,
  Sparkles,
  ExternalLink,
  Globe
} from '@lucide/vue'

const router = useRouter()
const message = useMessage()

const form = ref({
  name: '',
  type: ''
})

// 规则分类下拉选项 (供 n-select 组件使用)
const typeOptions = [
  { label: '全部类型', value: '' },
  { label: '视频 (Video)', value: 'video' },
  { label: '图片 (Picture)', value: 'picture' },
  { label: '小说 (Novel)', value: 'novel' }
]

const list = ref<RuleSchema[]>([])
const loading = ref(false)

// 导入导出相关的状态
const showImportModal = ref(false)
const importText = ref('')
const fileInputRef = ref<HTMLInputElement | null>(null)

const loadData = async () => {
  loading.value = true
  try {
    let data = await ruleService.getRules()

    if (form.value.name.trim()) {
      const searchName = form.value.name.toLowerCase().trim()
      data = data.filter((r) => r.name?.toLowerCase().includes(searchName))
    }
    if (form.value.type) {
      data = data.filter((r) => r.type === form.value.type)
    }

    list.value = data
  } catch (error) {
    console.error('Failed to load rules:', error)
    message.error('加载规则列表失败')
  } finally {
    loading.value = false
  }
}

const onReset = () => {
  form.value.name = ''
  form.value.type = ''
  loadData()
}

const onSearch = () => {
  loadData()
}

const onGoto = (row: RuleSchema) => {
  router.push(`/rules/edit?id=${row.id}`)
}

const toggleRule = async (row: RuleSchema, val: boolean) => {
  try {
    const nextVal = val ? 1 : 0
    await ruleService.toggleRuleEnabled(row.id, nextVal)
    row.enabled = nextVal
    message.success(val ? `已启用规则: ${row.name}` : `已禁用规则: ${row.name}`)
  } catch (error) {
    console.error('Failed to toggle rule state:', error)
    message.error('操作失败')
  }
}

const deleteRule = async (row: RuleSchema) => {
  try {
    await ruleService.deleteRule(row.id)
    message.success(`已成功删除规则: ${row.name}`)
    await loadData()
  } catch (error) {
    console.error('Failed to delete rule:', error)
    message.error('删除规则失败')
  }
}

// 导出/备份规则
const exportRules = (rulesToExport: RuleSchema[], filename: string) => {
  try {
    const cleaned = rulesToExport.map(({ id, created_at, updated_at, ...rest }) => rest)
    const jsonStr = JSON.stringify(cleaned, null, 2)
    const blob = new Blob([jsonStr], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = filename
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(url)
    message.success('规则导出成功')
  } catch (error: any) {
    message.error('导出失败: ' + error.message)
  }
}

const exportSingleRule = (row: RuleSchema) => {
  const filename = `${row.name || 'rule'}_backup.json`
  exportRules([row], filename)
}

const copySingleRule = async (row: RuleSchema) => {
  try {
    const { id, created_at, updated_at, ...rest } = row
    const jsonStr = JSON.stringify(rest, null, 2)
    if (navigator.clipboard && navigator.clipboard.writeText) {
      await navigator.clipboard.writeText(jsonStr)
    } else {
      const textArea = document.createElement('textarea')
      textArea.value = jsonStr
      document.body.appendChild(textArea)
      textArea.select()
      document.execCommand('copy')
      document.body.removeChild(textArea)
    }
    message.success(`已复制规则 [${row.name}]`)
  } catch (error: any) {
    message.error('复制失败: ' + error.message)
  }
}

const exportAllRules = () => {
  if (list.value.length === 0) {
    message.warning('当前列表中没有可导出的规则')
    return
  }
  const dateStr = new Date().toISOString().slice(0, 10)
  exportRules(list.value, `fluxforge_rules_all_${dateStr}.json`)
}

const triggerFileInput = () => {
  fileInputRef.value?.click()
}

const handleFileChange = (e: Event) => {
  const target = e.target as HTMLInputElement
  const file = target.files?.[0]
  if (!file) return

  const reader = new FileReader()
  reader.onload = (event) => {
    try {
      const content = event.target?.result as string
      processImportJson(content)
    } catch (err: any) {
      message.error('解析 JSON 文件失败: ' + err.message)
    } finally {
      if (fileInputRef.value) fileInputRef.value.value = ''
    }
  }
  reader.readAsText(file)
}

const processImportJson = async (jsonString: string) => {
  try {
    const parsed = JSON.parse(jsonString)
    const ruleArray = Array.isArray(parsed) ? parsed : [parsed]

    if (ruleArray.length === 0) {
      message.warning('文件中未包含有效的规则数据')
      return
    }

    let successCount = 0
    for (const item of ruleArray) {
      if (item && item.name && item.code) {
        await ruleService.saveRule({
          name: item.name,
          type: item.type || 'video',
          version: item.version || '1.0.0',
          author: item.author || '',
          description: item.description || '',
          baseUrl: item.baseUrl || '',
          code: item.code,
          enabled: item.enabled ? 1 : 0
        })
        successCount++
      }
    }

    message.success(`成功导入 ${successCount} 个规则`)
    showImportModal.value = false
    importText.value = ''
    await loadData()
  } catch (error: any) {
    message.error('导入规则失败: ' + error.message)
  }
}

const submitTextImport = () => {
  if (!importText.value.trim()) {
    message.warning('请先粘贴规则 JSON 文本')
    return
  }
  processImportJson(importText.value)
}

const getTypeConfig = (type: string) => {
  if (type === 'video' || type === '视频') {
    return {
      label: '视频',
      icon: Video,
      tagClass: 'bg-rose-50 dark:bg-rose-950/40 text-rose-600 dark:text-rose-400 border-rose-200/60 dark:border-rose-800/40',
      iconClass: 'bg-rose-500/10 dark:bg-rose-500/20 text-rose-600 dark:text-rose-400 border-rose-500/20'
    }
  }
  if (type === 'picture' || type === '图片') {
    return {
      label: '图片',
      icon: ImageIcon,
      tagClass: 'bg-amber-50 dark:bg-amber-950/40 text-amber-600 dark:text-amber-400 border-amber-200/60 dark:border-amber-800/40',
      iconClass: 'bg-amber-500/10 dark:bg-amber-500/20 text-amber-600 dark:text-amber-400 border-amber-500/20'
    }
  }
  if (type === 'novel' || type === '小说') {
    return {
      label: '小说',
      icon: BookOpen,
      tagClass: 'bg-indigo-50 dark:bg-indigo-950/40 text-indigo-600 dark:text-indigo-400 border-indigo-200/60 dark:border-indigo-800/40',
      iconClass: 'bg-indigo-500/10 dark:bg-indigo-500/20 text-indigo-600 dark:text-indigo-400 border-indigo-500/20'
    }
  }
  return {
    label: type || '通用',
    icon: Compass,
    tagClass: 'bg-emerald-50 dark:bg-emerald-950/40 text-emerald-600 dark:text-emerald-400 border-emerald-200/60 dark:border-emerald-800/40',
    iconClass: 'bg-emerald-500/10 dark:bg-emerald-500/20 text-emerald-600 dark:text-emerald-400 border-emerald-500/20'
  }
}

const formatDomain = (url?: string) => {
  if (!url) return ''
  try {
    return url.replace(/^https?:\/\//i, '').replace(/\/.*$/, '')
  } catch {
    return url
  }
}

loadData()
</script>

<template>
  <div class="h-full flex flex-col gap-3.5 max-w-[1600px] mx-auto w-full overflow-hidden">
    <!-- 顶部操作栏与统计 (固定在顶部，不随卡片列表滚动) -->
    <div class="glass-panel rounded-2xl p-4 sm:p-5 space-y-3 shadow-xs shrink-0">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <!-- 页面标题与统计 -->
        <div class="flex items-center gap-3">
          <div class="w-9 h-9 rounded-xl bg-gradient-to-tr from-emerald-600 via-teal-500 to-cyan-500 text-white flex items-center justify-center shadow-md shadow-emerald-500/25 flex-shrink-0">
            <Archive class="w-4.5 h-4.5" />
          </div>
          <div>
            <h1 class="text-base font-black tracking-tight text-zinc-900 dark:text-white flex items-center gap-2">
              <span>规则引擎管理</span>
              <span class="px-2 py-0.5 text-[10px] font-mono font-bold rounded-full bg-emerald-50/80 dark:bg-emerald-950/30 text-emerald-600 dark:text-emerald-400 border border-emerald-200/50 dark:border-emerald-800/30">
                ENGINE HUB
              </span>
            </h1>
            <p class="text-[11px] text-zinc-500 dark:text-zinc-400">
              管理系统内置与自定义的 JavaScript 沙箱抓取与解析规则
            </p>
          </div>
        </div>

        <!-- 动作按钮组 (新建、导入、导出) -->
        <div class="flex flex-wrap items-center gap-2">
          <n-button
            size="small"
            secondary
            class="!rounded-xl !font-bold"
            @click="showImportModal = true"
          >
            <template #icon>
              <Upload class="w-3.5 h-3.5" />
            </template>
            <span>导入规则</span>
          </n-button>

          <n-button
            size="small"
            secondary
            class="!rounded-xl !font-bold"
            @click="exportAllRules"
          >
            <template #icon>
              <Download class="w-3.5 h-3.5" />
            </template>
            <span>备份导出</span>
          </n-button>

          <n-button
            size="small"
            type="primary"
            class="!rounded-xl !font-bold"
            @click="router.push('/rules/edit')"
          >
            <template #icon>
              <Plus class="w-4 h-4" />
            </template>
            <span>新建规则</span>
          </n-button>
        </div>
      </div>

      <!-- 检索与筛选栏 -->
      <div class="pt-2.5 border-t border-emerald-100/50 dark:border-white/5 flex flex-wrap items-center justify-between gap-2.5">
        <div class="flex flex-wrap items-center gap-2.5">
          <!-- 规则名称检索输入框 (n-input 组件) -->
          <div class="w-48 sm:w-56">
            <n-input
              v-model:value="form.name"
              placeholder="搜索规则名称..."
              clearable
              class="!rounded-xl text-xs"
              @keyup.enter="onSearch"
              @clear="onSearch"
            >
              <template #prefix>
                <SearchIcon class="w-3.5 h-3.5 text-zinc-400" />
              </template>
            </n-input>
          </div>

          <!-- 规则类型选择框 (n-select 组件) -->
          <div class="w-32 sm:w-36">
            <n-select
              v-model:value="form.type"
              :options="typeOptions"
              class="!rounded-xl text-xs"
              @update:value="onSearch"
            />
          </div>

          <!-- 查询按钮 -->
          <n-button
            type="primary"
            size="small"
            class="!rounded-xl !font-bold"
            :loading="loading"
            @click="onSearch"
          >
            <template #icon>
              <SearchIcon class="w-3.5 h-3.5" />
            </template>
            <span>查询</span>
          </n-button>

          <!-- 重置按钮 -->
          <n-button
            quaternary
            size="small"
            class="!rounded-xl !font-semibold"
            :disabled="loading"
            @click="onReset"
          >
            重置
          </n-button>
        </div>

        <span class="text-[11px] text-zinc-400 whitespace-nowrap">
          已加载 <strong class="text-emerald-600 dark:text-emerald-400">{{ list.length }}</strong> 条规则
        </span>
      </div>
    </div>

    <!-- 下方卡片网格列表 (独立滚动区域，一行4列) -->
    <div class="flex-1 min-h-0 overflow-y-auto pr-1 pb-4">
      <!-- 1. 加载中骨架动画 (使用 Naive UI 原生 n-card 与 n-skeleton，一行4列) -->
      <div v-if="loading" class="grid gap-3.5 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        <n-card v-for="n in 8" :key="n" size="small" class="h-full flex flex-col justify-between !rounded-2xl">
          <div class="space-y-2 py-0.5">
            <div class="flex items-start justify-between gap-3">
              <div class="flex items-center gap-2.5 flex-1 min-w-0">
                <n-skeleton width="36px" height="36px" :sharp="false" class="rounded-xl shrink-0" />
                <div class="flex-1 space-y-1.5 min-w-0">
                  <n-skeleton text style="width: 60%" />
                  <n-skeleton text style="width: 35%" />
                </div>
              </div>
              <n-skeleton width="28px" height="16px" round class="shrink-0" />
            </div>
            <div class="space-y-1 pt-1">
              <n-skeleton text :repeat="2" />
            </div>
          </div>
          <template #action>
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-1.5">
                <n-skeleton circle width="22px" height="22px" />
                <n-skeleton circle width="22px" height="22px" />
                <n-skeleton circle width="22px" height="22px" />
              </div>
              <n-skeleton width="60px" height="24px" :sharp="false" class="rounded-lg" />
            </div>
          </template>
        </n-card>
      </div>

      <!-- 2. 无数据空白提示 -->
      <div v-else-if="list.length === 0" class="glass-panel rounded-2xl p-16 text-center max-w-md mx-auto my-12 flex flex-col items-center justify-center space-y-3">
        <Compass class="w-10 h-10 text-zinc-400" />
        <h3 class="text-sm font-bold text-zinc-800 dark:text-zinc-200">没有找到规则</h3>
        <p class="text-xs text-zinc-500 dark:text-zinc-400">可以点击上方“新建规则”导入规则。</p>
      </div>

      <!-- 3. 真实规则卡片网格 (一行4列) -->
      <div v-else class="grid gap-3.5 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        <div
          v-for="rule in list"
          :key="rule.id"
          class="glass-panel glass-panel-hover rounded-2xl p-4 flex flex-col justify-between h-full group relative border border-emerald-100/60 dark:border-white/5"
        >
          <!-- 上半部：图标、名称、开关、类型标签、域名胶囊、描述 -->
          <div class="space-y-2.5">
            <div class="flex items-start justify-between gap-2.5">
              <div class="flex items-center gap-2.5 min-w-0 flex-1">
                <div
                  class="w-9 h-9 rounded-xl flex items-center justify-center border flex-shrink-0 group-hover:scale-105 transition-transform"
                  :class="getTypeConfig(rule.type).iconClass"
                >
                  <component :is="getTypeConfig(rule.type).icon" class="w-4.5 h-4.5" />
                </div>
                <div class="min-w-0 flex-1">
                  <h3 class="text-sm font-bold text-zinc-900 dark:text-white truncate group-hover:text-emerald-600 dark:group-hover:text-emerald-400 transition-colors">
                    {{ rule.name }}
                  </h3>
                  <div class="flex items-center gap-1.5 mt-0.5 min-w-0">
                    <span
                      class="px-1.5 py-0.2 text-[10px] font-bold rounded border shrink-0"
                      :class="getTypeConfig(rule.type).tagClass"
                    >
                      {{ getTypeConfig(rule.type).label }}
                    </span>
                    <span class="text-[10px] font-mono text-zinc-400 shrink-0">
                      v{{ rule.version || '1.0.0' }}
                    </span>
                  </div>
                </div>
              </div>

              <!-- 启用状态 Switch 开关 -->
              <n-switch
                :value="rule.enabled === 1 || (rule.enabled as any) === true"
                size="small"
                class="shrink-0"
                @update:value="(val: boolean) => toggleRule(rule, val)"
              />
            </div>

            <!-- 规则描述 -->
            <p class="text-xs text-zinc-600 dark:text-zinc-300 line-clamp-2 leading-relaxed">
              {{ rule.description || '暂无详细描述信息' }}
            </p>
          </div>

          <!-- 下半部：动作栏 (左侧完整源站链接，右侧快捷按钮组与编辑配置) -->
          <div class="pt-2.5 mt-2.5 border-t border-emerald-100/50 dark:border-white/5 flex items-center justify-between gap-2 text-xs">
            <!-- 左侧：源站链接 (带 Globe 图标与文本) -->
            <a
              v-if="rule.baseUrl"
              :href="rule.baseUrl"
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center gap-1.5 text-xs font-mono text-zinc-400 hover:text-emerald-600 dark:hover:text-emerald-400 transition-colors truncate max-w-[130px] sm:max-w-[160px] min-w-0"
              :title="`访问源站: ${rule.baseUrl}`"
              @click.stop
            >
              <Globe class="w-3.5 h-3.5 shrink-0 opacity-60" />
              <span class="truncate">{{ formatDomain(rule.baseUrl) }}</span>
            </a>
            <span v-else class="text-[11px] text-zinc-400/40 select-none">无源站</span>

            <!-- 右侧：动作按钮组 (复制、导出、删除、编辑配置) -->
            <div class="flex items-center gap-0.5 shrink-0">
              <n-button
                quaternary
                circle
                size="small"
                class="text-zinc-400 hover:text-emerald-600"
                @click="copySingleRule(rule)"
                title="复制规则 JSON"
              >
                <template #icon>
                  <Copy class="w-3.5 h-3.5" />
                </template>
              </n-button>

              <n-button
                quaternary
                circle
                size="small"
                class="text-zinc-400 hover:text-emerald-600"
                @click="exportSingleRule(rule)"
                title="导出规则文件"
              >
                <template #icon>
                  <Download class="w-3.5 h-3.5" />
                </template>
              </n-button>

              <n-popconfirm @positive-click="deleteRule(rule)">
                <template #trigger>
                  <n-button
                    quaternary
                    circle
                    size="small"
                    class="text-zinc-400 hover:text-rose-500"
                    title="删除规则"
                  >
                    <template #icon>
                      <Trash2 class="w-3.5 h-3.5" />
                    </template>
                  </n-button>
                </template>
                确定要删除规则「{{ rule.name }}」吗？
              </n-popconfirm>

              <!-- 编辑配置主按钮 -->
              <n-button
                size="small"
                type="primary"
                secondary
                class="!rounded-xl !font-bold ml-1"
                @click="onGoto(rule)"
              >
                <template #icon>
                  <EditIcon class="w-3.5 h-3.5" />
                </template>
                <span>编辑</span>
              </n-button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- 导入规则弹窗 Modal -->
    <n-modal v-model:show="showImportModal" preset="card" title="导入规则配置" class="max-w-xl">
      <div class="space-y-4">
        <div>
          <label class="text-xs font-bold text-slate-700 dark:text-slate-300 block mb-1.5">
            方式一：从本地选择 JSON 文件
          </label>
          <input
            type="file"
            ref="fileInputRef"
            accept=".json"
            class="hidden"
            @change="handleFileChange"
          />
          <n-button
            dashed
            block
            size="large"
            class="!rounded-xl !h-12 !text-xs"
            @click="triggerFileInput"
          >
            <template #icon>
              <Upload class="w-4 h-4" />
            </template>
            <span>点击选择本地规则 .json 备份文件</span>
          </n-button>
        </div>

        <div>
          <label class="text-xs font-bold text-slate-700 dark:text-slate-300 block mb-1.5">
            方式二：粘贴规则 JSON 文本
          </label>
          <n-input
            v-model:value="importText"
            type="textarea"
            placeholder="在此粘贴包含单条或多条规则的 JSON 字符串..."
            :rows="6"
          />
        </div>

        <div class="flex justify-end gap-2 pt-2">
          <n-button
            size="small"
            quaternary
            class="!rounded-xl !font-bold"
            @click="showImportModal = false"
          >
            取消
          </n-button>
          <n-button
            size="small"
            type="primary"
            class="!rounded-xl !font-bold"
            @click="submitTextImport"
          >
            导入所填规则
          </n-button>
        </div>
      </div>
    </n-modal>
  </div>
</template>

<style scoped>
</style>