components {
  id: "Light"
  component: "/src/Modules/Render/Scene/Nodes/SpotLight.script"
}
embedded_components {
  id: "model1"
  type: "model"
  data: "mesh: \"/src/Modules/Render/Scene/Meshes/SpotLight.glb\"\n"
  "name: \"{{NAME}}\"\n"
  "materials {\n"
  "  name: \"default\"\n"
  "  material: \"/src/Modules/Render/Scene/Materials/Sphere.material\"\n"
  "}\n"
  ""
}
