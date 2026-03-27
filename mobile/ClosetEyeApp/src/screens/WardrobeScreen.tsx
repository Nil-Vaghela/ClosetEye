import React from "react";
import { View, Text, StyleSheet } from "react-native";

export default function WardrobeScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>Your Wardrobe</Text>
      <Text style={styles.subtitle}>All your clothing items will appear here</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: "#0f3460", alignItems: "center", justifyContent: "center" },
  title: { fontSize: 24, fontWeight: "bold", color: "#fff" },
  subtitle: { fontSize: 14, color: "#aaa", marginTop: 8 },
});
