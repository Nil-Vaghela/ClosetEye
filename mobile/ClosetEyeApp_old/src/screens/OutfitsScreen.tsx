import React from "react";
import { View, Text, StyleSheet } from "react-native";

export default function OutfitsScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>Outfit Combos</Text>
      <Text style={styles.subtitle}>AI-suggested outfits & your saved looks</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: "#0f3460", alignItems: "center", justifyContent: "center" },
  title: { fontSize: 24, fontWeight: "bold", color: "#fff" },
  subtitle: { fontSize: 14, color: "#aaa", marginTop: 8 },
});
