import React from "react";
import { createBottomTabNavigator } from "@react-navigation/bottom-tabs";
import WardrobeScreen from "../screens/WardrobeScreen";
import OutfitsScreen from "../screens/OutfitsScreen";
import CameraScreen from "../screens/CameraScreen";
import TryOnScreen from "../screens/TryOnScreen";
import ProfileScreen from "../screens/ProfileScreen";

const Tab = createBottomTabNavigator();

export default function RootNavigator() {
  return (
    <Tab.Navigator
      screenOptions={{
        headerStyle: { backgroundColor: "#1a1a2e" },
        headerTintColor: "#fff",
        tabBarActiveTintColor: "#e94560",
        tabBarInactiveTintColor: "#888",
        tabBarStyle: { backgroundColor: "#16213e" },
      }}
    >
      <Tab.Screen name="Wardrobe" component={WardrobeScreen} />
      <Tab.Screen name="Outfits" component={OutfitsScreen} />
      <Tab.Screen name="Add" component={CameraScreen} options={{ title: "Add Item" }} />
      <Tab.Screen name="Try On" component={TryOnScreen} />
      <Tab.Screen name="Profile" component={ProfileScreen} />
    </Tab.Navigator>
  );
}
