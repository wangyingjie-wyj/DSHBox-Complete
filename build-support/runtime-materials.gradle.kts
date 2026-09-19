import groovy.json.JsonSlurper
import java.nio.channels.FileChannel
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption
import java.security.MessageDigest
import org.gradle.api.GradleException

// Applied by :app so Android Studio and direct Gradle builds perform the same
// local material restoration as Build.ps1. No runtime material is downloaded.
data class BundledFile(
    val relativePath: String,
    val path: Path,
    val bytes: Long,
    val sha256: String,
)

data class BundledMaterial(val file: BundledFile, val parts: List<BundledFile>)

fun resolveBundledPath(root: Path, relativePath: String): Path {
    if (relativePath.isBlank() || ':' in relativePath ||
        relativePath.split('/', '\\').any { it == ".." }) {
        throw GradleException("Invalid repository-relative material path: $relativePath")
    }
    val relative = try {
        Paths.get(relativePath.replace('\\', '/'))
    } catch (error: RuntimeException) {
        throw GradleException("Invalid material path: $relativePath", error)
    }
    val resolved = root.resolve(relative).normalize()
    if (relative.isAbsolute || resolved == root || !resolved.startsWith(root)) {
        throw GradleException("Material path leaves the repository: $relativePath")
    }
    // Check existing ancestors too: Windows junctions can redirect a child
    // without Files.isSymbolicLink returning true for the final file itself.
    var current = root
    for (component in root.relativize(resolved)) {
        current = current.resolve(component)
        if (Files.exists(current, LinkOption.NOFOLLOW_LINKS)) {
            if (Files.isSymbolicLink(current) || !current.toRealPath().startsWith(root)) {
                throw GradleException("Material path crosses a link outside the repository: $relativePath")
            }
        }
    }
    return resolved
}

fun parseBundledFile(root: Path, raw: Any?): BundledFile {
    val record = raw as? Map<*, *>
        ?: throw GradleException("Every materials.lock.json file/chunk must be an object.")
    val relativePath = record["path"] as? String
        ?: throw GradleException("A materials.lock.json file/chunk is missing its path.")
    val bytes = (record["bytes"] as? Number)?.toString()?.toLongOrNull()
        ?.takeIf { it >= 0 }
        ?: throw GradleException("Invalid byte count for material: $relativePath")
    val sha256 = (record["sha256"] as? String)
        ?.takeIf { it.matches(Regex("[0-9a-f]{64}")) }
        ?: throw GradleException("Invalid lowercase SHA-256 for material: $relativePath")
    return BundledFile(relativePath, resolveBundledPath(root, relativePath), bytes, sha256)
}

fun bundledFileMatches(file: BundledFile): Boolean {
    if (!Files.isRegularFile(file.path, LinkOption.NOFOLLOW_LINKS) ||
        Files.size(file.path) != file.bytes) return false
    val digest = MessageDigest.getInstance("SHA-256")
    val buffer = ByteArray(1024 * 1024)
    Files.newInputStream(file.path).use { input ->
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            if (count > 0) digest.update(buffer, 0, count)
        }
    }
    val actualHash = digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
    return actualHash == file.sha256
}

val prepareBundledRuntime = tasks.register("prepareBundledRuntime") {
    group = "build setup"
    description = "Verify all locked local runtime materials and restore large files from repository chunks."
    // Deliberately verify on every build, including when Gradle considers its
    // asset-processing tasks up to date. SHA-256 is the source of truth.
    outputs.upToDateWhen { false }
    doLast {
        val root = rootProject.projectDir.toPath().toRealPath()
        val lockPath = resolveBundledPath(root, "materials.lock.json")
        if (!Files.isRegularFile(lockPath, LinkOption.NOFOLLOW_LINKS)) {
            throw GradleException("Missing materials.lock.json. Use the complete repository.")
        }
        val lock = try {
            Files.newBufferedReader(lockPath, Charsets.UTF_8).use { reader ->
                JsonSlurper().parse(reader) as? Map<*, *>
            }
        } catch (error: Exception) {
            throw GradleException("Cannot parse materials.lock.json.", error)
        } ?: throw GradleException("materials.lock.json must contain a JSON object.")
        val rawFiles = lock["files"] as? List<*>
        if (lock["schemaVersion"]?.toString() != "1" || rawFiles.isNullOrEmpty()) {
            throw GradleException("Expected materials.lock.json schemaVersion 1 and a non-empty files array.")
        }
        val materialPaths = mutableSetOf<Path>()
        val materials = rawFiles.map { raw ->
            val file = parseBundledFile(root, raw)
            if (!materialPaths.add(file.path)) {
                throw GradleException("Duplicate material path in lock file: ${file.relativePath}")
            }
            val record = raw as Map<*, *>
            val rawParts = when (val value = record["parts"]) {
                null -> emptyList<Any?>()
                is List<*> -> value
                else -> throw GradleException("Material parts must be an array: ${file.relativePath}")
            }
            BundledMaterial(file, rawParts.map { parseBundledFile(root, it) })
        }
        var restored = 0
        for (material in materials) {
            val file = material.file
            if (bundledFileMatches(file)) {
                logger.lifecycle("[verified] ${file.relativePath}")
                continue
            }
            if (material.parts.isEmpty()) {
                throw GradleException(
                    "Missing or damaged material: ${file.relativePath}. " +
                        "Restore it from a fresh copy of this complete repository. No runtime downloads are performed."
                )
            }
            var totalBytes = 0L
            for (part in material.parts) {
                if (!bundledFileMatches(part)) {
                    throw GradleException(
                        "Missing or damaged material chunk: ${part.relativePath}. " +
                            "Restore it from a fresh copy of this repository."
                    )
                }
                totalBytes = try {
                    Math.addExact(totalBytes, part.bytes)
                } catch (error: ArithmeticException) {
                    throw GradleException("Material chunk byte count overflow: ${file.relativePath}", error)
                }
            }
            if (totalBytes != file.bytes) {
                throw GradleException("Chunk lengths do not match the complete material: ${file.relativePath}")
            }
            // Check the destination again immediately before any writes.
            resolveBundledPath(root, file.relativePath)
            Files.createDirectories(file.path.parent)
            val temporary = Files.createTempFile(file.path.parent, file.path.fileName.toString() + ".restore-", ".tmp")
            try {
                logger.lifecycle("[restoring] ${file.relativePath} from ${material.parts.size} local chunks")
                Files.newOutputStream(temporary, StandardOpenOption.WRITE, StandardOpenOption.TRUNCATE_EXISTING).use { output ->
                    for (part in material.parts) {
                        Files.newInputStream(resolveBundledPath(root, part.relativePath)).use { input ->
                            input.copyTo(output, 1024 * 1024)
                        }
                    }
                }
                FileChannel.open(temporary, StandardOpenOption.WRITE).use { it.force(true) }
                if (!bundledFileMatches(file.copy(path = temporary))) {
                    throw GradleException("Reassembled material failed SHA-256 verification: ${file.relativePath}")
                }
                try {
                    Files.move(temporary, file.path, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
                } catch (error: AtomicMoveNotSupportedException) {
                    throw GradleException(
                        "The filesystem cannot atomically replace ${file.relativePath}. " +
                            "Move the complete repository to a local filesystem that supports atomic moves.", error
                    )
                }
                restored++
                logger.lifecycle("[restored] ${file.relativePath}")
            } finally {
                Files.deleteIfExists(temporary)
            }
        }
        logger.lifecycle("Runtime materials ready: ${materials.size} verified, $restored restored. All SHA-256 hashes match.")
    }
}

// configureEach also works if AGP creates preBuild after this script is applied.
tasks.matching { it.name == "preBuild" }.configureEach {
    dependsOn(prepareBundledRuntime)
}
