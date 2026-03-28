import React from "react";
import { View, Text, StyleSheet } from "react-native";

export default function TryOnScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>Virtual Try-On</Text>
      <Text style={styles.subtitle}>See how outfits look on you without wearing them</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: "#0f3460", alignItems: "center", justifyContent: "center" },
  title: { fontSize: 24, fontWeight: "bold", color: "#fff" },
  subtitle: { fontSize: 14, color: "#aaa", marginTop: 8, textAlign: "center", paddingHorizontal: 32 },
});
