package org.json;

import java.util.LinkedHashMap;
import java.util.Map;

public class JSONObject {
    private final Map<String, Object> values;

    public JSONObject() {
        values = new LinkedHashMap<String, Object>();
    }

    public JSONObject(String source) throws JSONException {
        Object parsed = Json.parse(source);
        if (!(parsed instanceof JSONObject)) {
            throw new JSONException("not a JSON object");
        }
        values = ((JSONObject) parsed).values;
    }

    JSONObject(Map<String, Object> values) {
        this.values = values;
    }

    public boolean has(String key) {
        return values.containsKey(key);
    }

    public Object opt(String key) {
        return values.get(key);
    }

    public String optString(String key) {
        return optString(key, "");
    }

    public String optString(String key, String defaultValue) {
        Object v = values.get(key);
        return v == null ? defaultValue : String.valueOf(v);
    }

    public long optLong(String key) {
        return optLong(key, 0);
    }

    public long optLong(String key, long defaultValue) {
        Object v = values.get(key);
        if (v instanceof Number) {
            return ((Number) v).longValue();
        }
        if (v instanceof String) {
            try {
                return Long.parseLong((String) v);
            } catch (NumberFormatException e) {
                return defaultValue;
            }
        }
        return defaultValue;
    }

    public long getLong(String key) throws JSONException {
        Object v = values.get(key);
        if (v instanceof Number) {
            return ((Number) v).longValue();
        }
        throw new JSONException("JSONObject[" + key + "] is not a number");
    }

    public String getString(String key) throws JSONException {
        Object v = values.get(key);
        if (v == null) {
            throw new JSONException("JSONObject[" + key + "] not found");
        }
        return String.valueOf(v);
    }

    public JSONArray getJSONArray(String key) throws JSONException {
        Object v = values.get(key);
        if (v instanceof JSONArray) {
            return (JSONArray) v;
        }
        throw new JSONException("JSONObject[" + key + "] is not a JSONArray");
    }

    public JSONArray optJSONArray(String key) {
        Object v = values.get(key);
        return (v instanceof JSONArray) ? (JSONArray) v : null;
    }

    public JSONObject optJSONObject(String key) {
        Object v = values.get(key);
        return (v instanceof JSONObject) ? (JSONObject) v : null;
    }

    public Object remove(String key) {
        return values.remove(key);
    }

    public JSONObject put(String key, Object value) {
        values.put(key, value);
        return this;
    }

    Map<String, Object> toMap() {
        return values;
    }

    @Override
    public String toString() {
        return Json.quoteObject(values);
    }
}