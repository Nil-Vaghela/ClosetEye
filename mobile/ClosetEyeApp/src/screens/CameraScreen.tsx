import React from "react";
import { View, Text, StyleSheet, TouchableOpacity } from "react-native";

export default function CameraScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>Add Clothing Item</Text>
      <TouchableOpacity style={styles.button}>
        <Text style={styles.buttonText}>Take Photo</Text>
      </TouchableOpacity>
      <TouchableOpacity style={[styles.button, styles.secondaryButton]}>
        <Text style={styles.buttonText}>Pick from Gallery</Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: "#0f3460", alignItems: "center", justifyContent: "center" },
  title: { fontSize: 24, fontWeight: "bold", color: "#fff", marginBottom: 32 },
  button: {
    backgroundColor: "#e94560",
    paddingVertical: 14,
    paddingHorizontal: 32,
    borderRadius: 12,
    marginBottom: 16,
    minWidth: 200,
    alignItems: "center",
  },
  secondaryButton: { backgroundColor: "#533483" },
  buttonText: { color: "#fff", fontSize: 16, fontWeight: "600" },
});
