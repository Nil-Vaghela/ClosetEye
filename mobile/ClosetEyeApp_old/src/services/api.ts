import axios from "axios";
import AsyncStorage from "@react-native-async-storage/async-storage";

const API_BASE = "http://localhost:8000/api/v1"; // change for production

const api = axios.create({
  baseURL: API_BASE,
  timeout: 30000,
  headers: { "Content-Type": "application/json" },
});

// Attach auth token to every request
api.interceptors.request.use(async (config) => {
  const token = await AsyncStorage.getItem("access_token");
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

export default api;

// ── Auth ────────────────────────────────────────────────────
export const authAPI = {
  register: (email: string, password: string, fullName?: string) =>
    api.post("/auth/register", { email, password, full_name: fullName }),

  login: (email: string, password: string) =>
    api.post("/auth/login", { email, password }),
};

// ── Wardrobe ───────────────────────────────────────────────
export const wardrobeAPI = {
  listItems: (category?: string) =>
    api.get("/wardrobe/items", { params: category ? { category } : {} }),

  getItem: (id: string) => api.get(`/wardrobe/items/${id}`),

  uploadItem: (formData: FormData) =>
    api.post("/wardrobe/items", formData, {
      headers: { "Content-Type": "multipart/form-data" },
    }),

  updateItem: (id: string, data: Record<string, unknown>) =>
    api.patch(`/wardrobe/items/${id}`, data),

  deleteItem: (id: string) => api.delete(`/wardrobe/items/${id}`),
};

// ── Outfits ────────────────────────────────────────────────
export const outfitsAPI = {
  list: () => api.get("/outfits/"),
  create: (data: { name?: string; occasion?: string; clothing_item_ids: string[] }) =>
    api.post("/outfits/", data),
  delete: (id: string) => api.delete(`/outfits/${id}`),
};

// ── Suggestions ────────────────────────────────────────────
export const suggestionsAPI = {
  get: (data: { occasion?: string; season?: string }) =>
    api.post("/suggestions/", data),
};

// ── Try-On ─────────────────────────────────────────────────
export const tryOnAPI = {
  generate: (formData: FormData) =>
    api.post("/tryon/", formData, {
      headers: { "Content-Type": "multipart/form-data" },
    }),
};
