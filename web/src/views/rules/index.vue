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
  RotateCcw
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

const loadData = () => {
  loading.value = true
  try {
    let data = ruleService.getRules()

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

const toggleRule = (row: RuleSchema, val: boolean) => {
  try {
    const nextVal = val ? 1 : 0
    ruleService.toggleRuleEnabled(row.id, nextVal)
    row.enabled = nextVal
    message.success(val ? `已启用规则: ${row.name}` : `已禁用规则: ${row.name}`)
  } catch (error) {
    console.error('Failed to toggle rule state:', error)
    message.error('操作失败')
  }
}

const deleteRule = (row: RuleSchema) => {
  try {
    ruleService.deleteRule(row.id)
    message.success(`已成功删除规则: ${row.name}`)
    loadData()
  } catch (error) {
    console.error('Failed to delete rule:', error)
    message.error('删除规则失败')
  }
}

const resetDefaults = () => {
  try {
    ruleService.resetToSeedRules()
    message.success('已成功重置为官方预置规则')
    loadData()
  } catch (e: any) {
    message.error('重置失败: ' + e.message)
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

const processImportJson = (jsonString: string) => {
  try {
    const parsed = JSON.parse(jsonString)
    const ruleArray = Array.isArray(parsed) ? parsed : [parsed]

    if (ruleArray.length === 0) {
      message.warning('文件中未包含有效的规则数据')
      return
    }

    let successCount = 0
    ruleArray.forEach((item: any) => {
      if (item && item.name && item.code) {
        ruleService.saveRule({
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
    })

    message.success(`成功导入 ${successCount} 个规则`)
    showImportModal.value = false
    importText.value = ''
    loadData()
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

const getCategoryIcon = (type: string) => {
  if (type === 'video' || type === '视频') return Video
  if (type === 'picture' || type === '图片') return ImageIcon
  if (type === 'novel' || type === '小说') return BookOpen
  return Compass
}

loadData()
</script>

<template>
  <div class="space-y-6 max-w-7xl mx-auto pb-12">
    <!-- 顶部操作栏与统计 (mori-box 风格) -->
    <div class="glass-panel rounded-2xl p-5 sm:p-6 space-y-4 shadow-sm">
      <div class="flex flex-wrap items-center justify-between gap-4">
        <!-- 页面标题与统计 -->
        <div class="flex items-center gap-3">
          <div class="w-10 h-10 rounded-2xl bg-gradient-to-tr from-emerald-600 via-teal-500 to-cyan-500 text-white flex items-center justify-center shadow-md shadow-emerald-500/25 flex-shrink-0">
            <Archive class="w-5 h-5" />
          </div>
          <div>
            <h1 class="text-base sm:text-lg font-black tracking-tight text-zinc-900 dark:text-white flex items-center gap-2">
              <span>规则引擎管理</span>
              <span class="px-2 py-0.5 text-[10px] font-mono font-bold rounded-full bg-emerald-50/80 dark:bg-emerald-950/30 text-emerald-600 dark:text-emerald-400 border border-emerald-200/50 dark:border-emerald-800/30">
                ENGINE HUB
              </span>
            </h1>
            <p class="text-xs text-zinc-500 dark:text-zinc-400 mt-0.5">
              管理系统内置与自定义的 JavaScript 沙箱抓取与解析规则
            </p>
          </div>
        </div>

        <!-- 动作按钮组 (新建、导入、导出、重置预置) -->
        <div class="flex flex-wrap items-center gap-2">
          <n-button
            size="small"
            secondary
            class="!rounded-xl !font-bold"
            @click="resetDefaults"
            title="重置回默认预置规则"
          >
            <template #icon>
              <RotateCcw class="w-3.5 h-3.5" />
            </template>
            <span class="hidden sm:inline">重置预置</span>
          </n-button>

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
      <div class="pt-3 border-t border-emerald-100/50 dark:border-white/5 flex flex-wrap items-center justify-between gap-3">
        <div class="flex flex-wrap items-center gap-2.5">
          <!-- 规则名称检索输入框 (n-input 组件) -->
          <div class="w-48 sm:w-56">
            <n-input
              v-model:value="form.name"
              placeholder="搜索规则名称..."
              clearable
              class="!rounded-xl"
              @keyup.enter="onSearch"
              @clear="onSearch"
            >
              <template #prefix>
                <SearchIcon class="w-4 h-4 text-zinc-400" />
              </template>
            </n-input>
          </div>

          <!-- 规则类型选择框 (n-select 组件) -->
          <div class="w-36 sm:w-40">
            <n-select
              v-model:value="form.type"
              :options="typeOptions"
              class="!rounded-xl"
              @update:value="onSearch"
            />
          </div>

          <!-- 筛选按钮 -->
          <n-button
            type="primary"
            class="!rounded-xl !font-bold"
            @click="onSearch"
          >
            筛选
          </n-button>

          <!-- 重置按钮 -->
          <n-button
            quaternary
            class="!rounded-xl !font-semibold"
            @click="onReset"
          >
            重置
          </n-button>
        </div>

        <span class="text-xs text-zinc-400 whitespace-nowrap">
          已加载 <strong class="text-emerald-600 dark:text-emerald-400">{{ list.length }}</strong> 条规则
        </span>
      </div>
    </div>

    <!-- 规则卡片网格列表 (mori-box 风格) -->
    <div class="space-y-4">
      <div v-if="list.length === 0" class="glass-panel rounded-2xl p-16 text-center max-w-md mx-auto my-12 flex flex-col items-center justify-center space-y-3">
        <Compass class="w-10 h-10 text-zinc-400" />
        <h3 class="text-sm font-bold text-zinc-800 dark:text-zinc-200">没有找到规则</h3>
        <p class="text-xs text-zinc-500 dark:text-zinc-400">可以点击上方“新建规则”或“重置预置”导入规则。</p>
      </div>

      <div v-else class="grid gap-4 grid-cols-1 md:grid-cols-2 lg:grid-cols-3">
        <div
          v-for="rule in list"
          :key="rule.id"
          class="glass-panel glass-panel-hover rounded-2xl p-5 flex flex-col justify-between h-full group relative border border-emerald-100/60 dark:border-white/5"
        >
          <!-- 上半部：图标、名称、开关、描述 -->
          <div class="space-y-3">
            <div class="flex items-start justify-between gap-3">
              <div class="flex items-center gap-3 min-w-0">
                <div class="w-10 h-10 rounded-xl bg-emerald-500/10 dark:bg-emerald-500/20 text-emerald-600 dark:text-emerald-400 flex items-center justify-center border border-emerald-500/20 flex-shrink-0 group-hover:scale-105 transition-transform">
                  <component :is="getCategoryIcon(rule.type)" class="w-5 h-5" />
                </div>
                <div class="min-w-0">
                  <h3 class="text-sm font-bold text-zinc-900 dark:text-white truncate group-hover:text-emerald-600 dark:group-hover:text-emerald-400 transition-colors">
                    {{ rule.name }}
                  </h3>
                  <div class="flex items-center gap-2 mt-0.5">
                    <span class="text-[10px] font-mono text-zinc-400">
                      v{{ rule.version || '1.0.0' }} • {{ rule.type === 'video' ? '视频' : rule.type === 'picture' ? '图片' : '小说' }}
                    </span>
                  </div>
                </div>
              </div>

              <!-- 启用状态 Switch 开关 -->
              <n-switch
                :value="rule.enabled === 1 || (rule.enabled as any) === true"
                size="small"
                @update:value="(val: boolean) => toggleRule(rule, val)"
              />
            </div>

            <!-- 规则描述 -->
            <p class="text-xs text-zinc-600 dark:text-zinc-300 line-clamp-2 leading-relaxed">
              {{ rule.description || '暂无详细描述信息' }}
            </p>

            <!-- 站点域名 -->
            <div v-if="rule.baseUrl" class="text-[11px] font-mono text-zinc-400 truncate flex items-center gap-1">
              <span class="opacity-60">源站:</span>
              <span class="truncate">{{ rule.baseUrl }}</span>
            </div>
          </div>

          <!-- 下半部：动作栏 (编辑、复制、导出、删除) -->
          <div class="pt-4 mt-4 border-t border-emerald-100/50 dark:border-white/5 flex items-center justify-between text-xs">
            <div class="flex items-center gap-1">
              <n-button
                quaternary
                circle
                size="small"
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
            </div>

            <!-- 编辑配置主按钮 -->
            <n-button
              size="small"
              type="primary"
              secondary
              class="!rounded-xl !font-bold"
              @click="onGoto(rule)"
            >
              <template #icon>
                <EditIcon class="w-3.5 h-3.5" />
              </template>
              <span>编辑配置</span>
            </n-button>
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