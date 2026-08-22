import { ref } from 'vue'
import type { MediaItem } from '@/types/rule'

// 缓存最近点击的媒体上下文数据，键为 `${ruleId}:${key}`
const contextMap = ref<Map<string, Partial<MediaItem>>>(new Map())

export const useMediaContext = () => {
  /**
   * 存储跳转前的媒体项上下文数据 (用于 0ms 秒开占位)
   */
  const setContext = (ruleId: number | string, key: string, item: Partial<MediaItem>): void => {
    if (!ruleId || !key) return
    const sessionKey = `${ruleId}:${key}`
    contextMap.value.set(sessionKey, { ...item })
  }

  /**
   * 获取缓存的媒体项上下文数据
   */
  const getContext = (ruleId: number | string, key: string): Partial<MediaItem> | undefined => {
    if (!ruleId || !key) return undefined
    const sessionKey = `${ruleId}:${key}`
    return contextMap.value.get(sessionKey)
  }

  /**
   * 清除特定缓存
   */
  const clearContext = (ruleId: number | string, key: string): void => {
    const sessionKey = `${ruleId}:${key}`
    contextMap.value.delete(sessionKey)
  }

  return {
    setContext,
    getContext,
    clearContext
  }
}
