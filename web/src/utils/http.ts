import axios, { type AxiosRequestConfig } from 'axios'

const http = axios.create({
  baseURL: import.meta.env.VITE_BASE_URL || '/api',
})

http.interceptors.request.use(config => {
  return config
})

/**
 * Axios 响应拦截器，返回 res.data
 * @template T
 * @param {import('axios').AxiosResponse} response
 * @returns {T} 返回的 data
 */
http.interceptors.response.use(res => {
  const data = res.data
  if (data?.success === false) {
    window.$message.error(data.message)
  }
  return Promise.resolve(data)
}, err => {
  const res = err.response
  let status = res?.status ?? 0
  if (status > 200 && status <= 500) {
    window.$message.error(res?.data?.['message'])
  } else if (res?.code == 'ERR_NETWORK') {
    window.$message.error('网络错误，请稍后再试')
  } else {
    window.$message.error('服务器错误，请稍后再试')
  }

  return Promise.reject(err)
})

const get = async(url: string, config?: AxiosRequestConfig): Promise<any> => {
  return http.get(url, config)
}

const post = async(url: string, data?: any, config?: AxiosRequestConfig): Promise<any> => {
  return http.post(url, data, config)
}

const request = async (config: AxiosRequestConfig): Promise<any> => {
  return http.request(config)
}

const put = async (url: string, data?: any, config?: AxiosRequestConfig): Promise<any> => {
  return http.put(url, data, config)
}

const patch = async (url: string, data?: any, config?: AxiosRequestConfig): Promise<any> => {
  return http.patch(url, data, config)
}

const del = async (url: string, config?: AxiosRequestConfig): Promise<any> => {
  return http.delete(url, config)
}

export const baseURL = http.defaults.baseURL
export const headers = http.defaults.headers.common

export default {
  baseURL,
  headers,
  get,
  post,
  request,
  put,
  patch,
  delete: del
}